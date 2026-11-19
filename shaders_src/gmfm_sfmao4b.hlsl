// GM:FM (b0.2.6) — Source Filmmaker's ambient occlusion, Shader Model 2 (ps_2_b, for DirectX
// level 90 too). Read out of SFM itself: the shader sfm_ambientocclusion_ps30 and the code of its
// material in stdshader_dx9.dll that fills the constants (c10 = RADIUS, FARZ / (RADIUS x
// STRENGTH), FARZ, BIAS x FARZ; the kernel made once per session from rand()). The same here:
//  * 16 directions: 4 x 4 strata over the whole sphere, each of a random length below 1,
//    reflected in a random vector of the pixel and mirrored into the hemisphere of the normal;
//  * the start point sits BIAS x its distance off the surface along the normal, the directions
//    reach RADIUS / 4 from it;
//  * a direction counts when its point is behind what the camera sees there, by
//    saturate(1 / (dz / (RADIUS x STRENGTH) + 0.618) - 0.618): 1 right at the surface, 0 at
//    RADIUS x STRENGTH behind it — STRENGTH is how deep the occluders reach, not a darkness;
//  * visibility = (1 - occluded / 16)^2.
// SFM draws the normals in a pass of its own; here the normal comes from the depth around the
// pixel (the side with the smaller step, so that an edge does not bend it). The random vector
// is one per pixel (SFM's noise texture is sampled one texel per pixel), moved by the seed of
// the pass (SFM's $JITTERSEED: a new noise in every pass of a progressive render).
// s0: depth from GM:FM's depth pass: R = (view depth / far)^2; 1 = sky / nothing
// c0: x = radius (units), y = 1 / (radius x strength), z = far (units), w = bias
// c1: x = tan(half horizontal fov), y = tan(half vertical fov), z = 1 / width, w = 1 / height
// c2: xy = the seed of this pass
// Output: R = G = B = visibility (1 = open, 0 = fully occluded).
sampler DepthSampler : register(s0);
const float4 g_Params : register(c0);
const float4 g_View   : register(c1);
const float4 g_Seed   : register(c2);

// (b0.2.7) The depth as the float target holds it: (view depth / far)^2. PACKED_DEPTH (the *_pk
// shaders, Linux / macOS: no float target can be drawn into there): three 8-bit fog passes (half a
// unit to 128 units, 2 units to 512, 8 units to 2048; past that, open as the sky), packed and then
// smoothed into 16 bits by gmfm_depthsmooth (R = high byte, G = low byte of depth / far).
// quantStep: the size of one step of the fog passes there, in units (0: float depth).
#ifdef PACKED_DEPTH
#define NORMAL_STEP 1.0
// c3.xy (b0.2.7): a quarter of a texel. The depth is point sampled, and under the game's OpenGL
// layer the quad's coordinates fall on the borders between texels: a lookup there took the row
// above or below at random — rows doubled and skipped, the smoothing and the normals in steps
// (measured: row-to-row depth 0, 3, 0, 2.5 … for an even 1.4). A quarter texel in is inside the
// right one whether the coordinate sits on a border or a centre.
const float4 g_Texel : register(c3);
float rawDepth(float2 uv)
{
	// smoothed into 16 bits by gmfm_depthsmooth: R = high byte, G = low byte of depth / far
	float2 t = tex2D(DepthSampler, uv + g_Texel.xy).rg;
	float d = t.r + t.g / 255.0;
	return d * d;
}
float quantStep(float dUnits, float far)
{
	return (dUnits < 0.9 * far / 64.0) ? far / (64.0 * 255.0) : ((dUnits < 0.9 * far / 16.0) ? far / (16.0 * 255.0) : far / (4.0 * 255.0));
}
#else
#define NORMAL_STEP 1.0
float rawDepth(float2 uv) { return tex2D(DepthSampler, uv).r; }
float quantStep(float dUnits, float far) { return 0.0; }
#endif

static const float3 KERNEL[16] = {
	float3(0.382308, 0.077423, 0.225959), float3(-0.209320, 0.143444, 0.244130),
	float3(-0.022970, -0.001453, 0.052189), float3(0.302899, -0.102654, 0.516715),
	float3(0.550876, 0.539325, 0.138753), float3(-0.714034, 0.338826, 0.139745),
	float3(-0.497173, -0.021178, 0.150494), float3(0.287340, -0.013537, 0.091794),
	float3(0.728124, 0.330240, -0.357917), float3(-0.589695, 0.338579, -0.256286),
	float3(-0.821951, -0.141576, -0.467010), float3(0.855837, -0.012556, -0.352618),
	float3(0.066623, 0.026890, -0.534547), float3(-0.026742, 0.117549, -0.075678),
	float3(-0.348320, -0.121933, -0.278072), float3(0.063688, -0.113251, -0.196207)
};

float depthAt(float2 uv)
{
	// max(): the blended value can come out a hair below zero next to the camera (sqrt -> NaN)
	return sqrt(max(rawDepth(uv), 0.0)) * g_Params.z;
}

// sin() is not there in ps_2_b: Dave Hoskins' hash12
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
	float sky = rawDepth(uv);
	float3 p = viewPos(uv);

	float3 pr = viewPos(uv + float2(g_View.z * NORMAL_STEP, 0));
	float3 pl = viewPos(uv - float2(g_View.z * NORMAL_STEP, 0));
	float3 pd = viewPos(uv + float2(0, g_View.w * NORMAL_STEP));
	float3 pu = viewPos(uv - float2(0, g_View.w * NORMAL_STEP));
	float3 dx = (length(pr - p) < length(p - pl)) ? (pr - p) : (p - pl);
	float3 dy = (length(pd - p) < length(p - pu)) ? (pd - p) : (p - pu);
	float3 n = normalize(cross(dy, dx) + float3(0, 0, -1e-6));
	n = (dot(n, p) > 0) ? -n : n;
	// SFM: base = position + normal x depth x BIAS
	float3 o = p + n * (p.z * g_Params.w);

	// the random vector of this pixel (no VPOS in Shader Model 2: the pixel from the coordinates)
	float2 cell = floor(uv / g_View.zw) + g_Seed.xy;
	float h1 = hash(cell);
	float h2 = hash(cell + 17.0);
	float h3 = hash(cell + 41.0);
	float3 rnd = normalize(float3(h1, h2, h3) * 2.0 - 1.0 + 0.0001);

	float reach = g_Params.x * 0.25;
	float occ = 0;
	[unroll] for (int i = 0; i < 16; i++)
	{
		float3 k = reflect(KERNEL[i], rnd);
		float kn = dot(k, n);
		k = (kn < 0) ? k - 2.0 * kn * n : k;
		float3 s = o + k * reach;
		s.z = max(s.z, 1.0);
		float2 su = s.xy / (s.z * g_View.xy) * float2(0.5, -0.5) + 0.5;
		float seen = depthAt(su);
		// packed depth (b0.2.7): a point behind by less than half a step of the depth is not hidden —
		// the steps of a flat floor read as ledges and darkened it in bands
		float dz = s.z - seen - 0.5 * quantStep(seen, g_Params.z);
		float c = saturate(1.0 / (dz * g_Params.y + 0.618) - 0.618);
		occ += (dz > 0) ? c : 0;
	}
	float vis = 1.0 - occ * 0.0625;
	vis *= vis;
	return (sky > 0.999) ? float4(1, 1, 1, 1) : float4(vis, vis, vis, 1);
}
