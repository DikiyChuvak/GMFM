// GM:FM (b0.2.1) — the Shader Model 2 (ps_2_b) form of gmfm_sfmao3_ps30, for games at DirectX
// level 90 (Linux, ToGL), where a ps_3_0 shader is not run at all: the texture coordinates of
// screenspace_general's own vertex shader instead of VPOS, SAMPLES points of the kernel (the
// instruction limit), no early outs. Otherwise the same:
// ambient occlusion after Source Filmmaker's own (ssao_ps30, the 25-sample
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

#ifndef SAMPLES
#define SAMPLES 25
#endif

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
	return sqrt(max(tex2D(DepthSampler, uv).r, 0.0)) * g_Params.z;
}

// sin() is not there in ps_2_b: Dave Hoskins' hash12 (as the film grain)
float hash(float2 q)
{
	float3 p3 = frac(float3(q.x, q.y, q.x) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return frac((p3.x + p3.y) * p3.z);
}

float3 viewPos(float2 uv)
{
	float d = depthAt(uv);
	float2 ndc = uv * float2(2.0, -2.0) + float2(-1.0, 1.0);
	return float3(ndc.x * g_View.x * d, ndc.y * g_View.y * d, d);
}

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float sky = tex2D(DepthSampler, uv).r;
	float3 p = viewPos(uv);

	float3 pr = viewPos(uv + float2(g_View.z, 0));
	float3 pl = viewPos(uv - float2(g_View.z, 0));
	float3 pd = viewPos(uv + float2(0, g_View.w));
	float3 pu = viewPos(uv - float2(0, g_View.w));
	float3 dx = (length(pr - p) < length(p - pl)) ? (pr - p) : (p - pl);
	float3 dy = (length(pd - p) < length(p - pu)) ? (pd - p) : (p - pu);
	float3 n = normalize(cross(dy, dx) + float3(0, 0, -1e-6));
	n = (dot(n, p) > 0) ? -n : n;
	float3 o = p + n * g_Params.w;

	// the 4 x 4 tile from the pixel number (no VPOS in Shader Model 2)
	float2 cell = floor(fmod(uv / g_View.zw, 4.0)) + g_Seed.xy;
	float h = hash(cell);
	float h2 = hash(cell + 17.0);
	float3 rnd = normalize(float3(h * 2 - 1, h2 * 2 - 1, frac(h + h2 * 1.618) * 2 - 1) + 0.0001);

	float radius = g_Params.x;
	float occ = 0;
	[unroll] for (int i = 0; i < SAMPLES; i++)
	{
		float3 k = reflect(KERNEL[i * 25 / SAMPLES], rnd);
		k = (dot(k, n) < 0) ? -k : k;
		float3 s = o + k * radius;
		s.z = max(s.z, 1.0);
		float2 su = s.xy / (s.z * g_View.xy) * float2(0.5, -0.5) + 0.5;
		float d = depthAt(su);
		float diff = (s.z - d - max(1.0, d * 0.006)) / radius;
		occ += (diff > 0) ? min(1.0, 1.0 / diff) : 0;
	}
	float vis = saturate(1.0 - g_Params.y * occ / SAMPLES);
	return (sky > 0.999) ? float4(1, 1, 1, 1) : float4(vis, vis, vis, 1);
}
