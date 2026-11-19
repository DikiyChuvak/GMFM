// SPeditor — depth-aware blur of the occlusion along one direction.
// s0: occlusion, s1: depth (as in speditor_ao.hlsl)
// c0: xy = one texel along the blur direction, z = far (units), w = depth tolerance (units)
sampler AOSampler    : register(s0);
sampler DepthSampler : register(s1);
const float4 g_Params : register(c0);

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

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float d0 = sqrt(max(rawDepth(uv), 0.0)) * g_Params.z;
	float sum = 0, wsum = 0;
	[unroll] for (int i = -4; i <= 4; i++)
	{
		float2 q = uv + g_Params.xy * i;
		float d = sqrt(max(rawDepth(q), 0.0)) * g_Params.z;
		float w = (5.0 - abs(i)) * saturate(1.0 - abs(d - d0) / (g_Params.w * max(d0, 1.0) * 0.01 + 0.5));
		sum += tex2D(AOSampler, q).r * w;
		wsum += w;
	}
	float v = sum / max(wsum, 0.0001);
	return float4(v, v, v, 1);
}
