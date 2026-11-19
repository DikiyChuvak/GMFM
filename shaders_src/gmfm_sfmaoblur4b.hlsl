// GM:FM (b0.2.6) — SFM's blur of the occlusion (sfm_ao_blur_ps30), Shader Model 2: 16 points
// of SFM's Poisson disc (the centre and 15 around it) turned by a random angle of the pixel,
// each weighed down by a smooth step of its depth difference, so the occlusion is smoothed along
// surfaces but not across their edges. SFM's disc is 0.00416 of the frame's height (Lua passes it
// in texels). Unlike SFM the samples are weighed in the sum as well, not only in the total.
// s0: occlusion, s1: depth (R = (depth / far)^2)
// c0: xy = one texel, z = far (units), w = radius of the disc (texels)
// c1: x = depth tolerance (part of the depth), yz = the seed of the pass (the turn of the disc)
sampler AOSampler    : register(s0);
sampler DepthSampler : register(s1);
const float4 g_Params : register(c0);
const float4 g_Tol    : register(c1);

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

static const float2 DISC[15] = {
	float2(0.2329, 0.3995), float2(-0.4577, 0.7647), float2(0.4205, -0.5768), float2(-0.5215, 0.1854),
	float2(0.0666, -0.5564), float2(-0.4112, -0.3311), float2(-0.9055, -0.0360), float2(0.5592, 0.3459),
	float2(-0.4325, -0.8857), float2(0.3090, -0.8646), float2(0.3752, 0.0627), float2(0.0969, 0.7054),
	float2(-0.5887, -0.1100), float2(-0.8438, 0.2706), float2(-0.1245, -0.3302)
};

float hash(float2 q)
{
	float3 p3 = frac(float3(q.x, q.y, q.x) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return frac((p3.x + p3.y) * p3.z);
}

float depthAt(float2 uv) { return sqrt(max(rawDepth(uv), 0.0)) * g_Params.z; }

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float d0 = depthAt(uv);
	// a turn per pixel: a random unit vector (no sin() in ps_2_b)
	float2 cell = floor(uv / g_Params.xy) + g_Tol.yz;
	float2 cs = normalize(float2(hash(cell + 3.0), hash(cell + 5.0)) * 2.0 - 1.0 + 0.0001);
	float2x2 rot = float2x2(cs.x, -cs.y, cs.y, cs.x);
	float sum = tex2D(AOSampler, uv).r, wsum = 1;
	float tol = max(d0 * g_Tol.x, 2.0);
	[unroll] for (int i = 0; i < 15; i++)
	{
		float2 q = uv + mul(rot, DISC[i]) * g_Params.xy * g_Params.w;
		float t = saturate(abs(depthAt(q) - d0) / tol);
		float w = 1.0 - t * t * (3.0 - 2.0 * t);
		sum += tex2D(AOSampler, q).r * w;
		wsum += w;
	}
	float v = sum / wsum;
	return float4(v, v, v, 1);
}
