// GM:FM (b0.2) — ambient occlusion after Source Filmmaker's own (ssao_ps30, the 25-sample
// variant that takes only the depth): the normal of a pixel from the depth around it, a
// hemisphere of 25 fixed points (SFM's kernel) turned by a 4 x 4 pattern of random vectors,
// every point that lands behind the surface seen there counts, less the farther behind it is.
// s0: depth from GM:FM's depth pass: R = (view depth / far)^2; 1 = sky / nothing
// c0: x = radius (units), y = strength, z = far (units), w = bias (units along the normal)
// c1: x = tan(half horizontal fov), y = tan(half vertical fov), z = 1 / width, w = 1 / height
// c2: xy = the seed of this pass (b0.2 round 6: SFM's progressive render takes a new set of
//     directions every pass and averages the passes — 0, 0 gives the stable pattern)
// Output: R = G = B = visibility (1 = open, 0 = fully occluded).
sampler DepthSampler : register(s0);
const float4 g_Params : register(c0);
const float4 g_View   : register(c1);
const float4 g_Seed   : register(c2);

#define SAMPLES 25

static const float3 KERNEL[25] = {
	float3(0.615195, 0.099185, 0.468574), float3(-0.246664, 0.495551, 0.636662), float3(-0.302699, 0.197356, 0.928992),
	float3(0.025013, -0.473721, 0.879973), float3(0.329761, -0.243882, 0.453554), float3(0.228839, 0.289674, 0.133150),
	float3(0.066389, 0.230785, 0.114893), float3(-0.221339, -0.148409, 0.131756), float3(-0.457569, -0.666197, 0.229464),
	float3(0.020583, -0.009117, 0.007547), float3(0.365528, 0.050190, -0.071732), float3(-0.073882, 0.055014, -0.009701),
	float3(-0.630459, 0.209926, -0.130613), float3(-0.038274, -0.039986, 0.009818), float3(0.004809, -0.007283, 0.001042),
	float3(0.745164, 0.323719, -0.429083), float3(-0.015386, 0.267425, -0.066036), float3(-0.212754, 0.079506, -0.151285),
	float3(-0.096176, -0.522937, -0.250845), float3(0.489685, -0.464403, -0.149240), float3(0.306264, 0.196200, -0.754520),
	float3(-0.131151, 0.139137, -0.700880), float3(-0.362332, -0.100502, -0.306237), float3(-0.043645, -0.153336, -0.129443),
	float3(0.293372, -0.170633, -0.661786)
};

float depthAt(float2 uv)
{
	// max(): the blended value can come out a hair below zero next to the camera (sqrt -> NaN)
	return sqrt(max(tex2Dlod(DepthSampler, float4(uv, 0, 0)).r, 0.0)) * g_Params.z;
}

float3 viewPos(float2 uv)
{
	float d = depthAt(uv);
	float2 ndc = uv * float2(2.0, -2.0) + float2(-1.0, 1.0);
	return float3(ndc.x * g_View.x * d, ndc.y * g_View.y * d, d);
}

float4 main(float2 uvIn : TEXCOORD0, float2 vpos : VPOS) : COLOR
{
	// the place on the target from the pixel itself: the texture coordinates of the quad are
	// not dependable in every pass the engine draws (a render gave one value for the whole frame)
	float2 uv = (vpos + 0.5) * g_View.zw;
	if (tex2Dlod(DepthSampler, float4(uv, 0, 0)).r > 0.999) return float4(1, 1, 1, 1);
	float3 p = viewPos(uv);

	// the normal from the nearer neighbour on each axis (as SFM: clean at the edges)
	float3 pr = viewPos(uv + float2(g_View.z, 0));
	float3 pl = viewPos(uv - float2(g_View.z, 0));
	float3 pd = viewPos(uv + float2(0, g_View.w));
	float3 pu = viewPos(uv - float2(0, g_View.w));
	float3 dx = (length(pr - p) < length(p - pl)) ? (pr - p) : (p - pl);
	float3 dy = (length(pd - p) < length(p - pu)) ? (pd - p) : (p - pu);
	float3 nc = cross(dy, dx);
	float cl = length(nc);
	float3 n = (cl > 1e-6) ? nc / cl : float3(0, 0, -1);
	if (dot(n, p) > 0) n = -n;     // towards the camera
	// the start a little off the surface (SFM moves it along the normal too)
	float3 o = p + n * g_Params.w;

	// SFM's random vector: a 4 x 4 tile of it (its noise texture), stable from frame to frame;
	// every pass of a progressive render moves the tile by its seed
	float2 cell = floor(fmod(vpos, 4.0)) + g_Seed.xy;
	float h = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
	float h2 = frac(sin(dot(cell, float2(39.3468, 11.1351))) * 24634.6345);
	float3 rnd = normalize(float3(h * 2 - 1, h2 * 2 - 1, frac(h + h2 * 1.618) * 2 - 1) + 0.0001);

	float radius = g_Params.x;
	float occ = 0;
	for (int i = 0; i < SAMPLES; i++)
	{
		float3 k = reflect(KERNEL[i], rnd);
		// into the half facing out of the surface
		if (dot(k, n) < 0) k = -k;
		float3 s = o + k * radius;
		if (s.z < 1.0) continue;
		float2 su = float2(s.x / (s.z * g_View.x), s.y / (s.z * g_View.y)) * float2(0.5, -0.5) + 0.5;
		if (su.x < 0 || su.x > 1 || su.y < 0 || su.y > 1) continue;     // off the frame: open
		float d = depthAt(su);
		// SFM reads an exact depth buffer; this one is rebuilt from fog, a hair off on flat
		// ground far away — so a point counts only when it is behind by more than that
		float diff = (s.z - d - max(1.0, d * 0.006)) / radius;
		// SFM's range check: behind the surface counts fully within the radius, then as 1 / x
		if (diff > 0) occ += min(1.0, 1.0 / diff);
	}
	float vis = saturate(1.0 - g_Params.y * occ / SAMPLES);
	if (!(vis == vis)) vis = 1.0;
	return float4(vis, vis, vis, 1);
}
