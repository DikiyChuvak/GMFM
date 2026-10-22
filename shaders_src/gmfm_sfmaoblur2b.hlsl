// GM:FM (b0.2.1) — the Shader Model 2 (ps_2_b) form of gmfm_sfmao_blur2_ps30 for DirectX level
// 90 (texture coordinates instead of VPOS, a hash instead of sin()). Otherwise the same:
// SFM's blur of the occlusion (sfm_ao_blur_ps30): 16 points of a Poisson disc
// around the pixel, turned per pixel, each weighed down when its depth differs (a smooth
// step), so the occlusion is smoothed along surfaces but not across their edges. Unlike SFM
// the samples are weighed in the sum as well, not only in the total.
// s0: occlusion, s1: depth (R = (depth / far)^2)
// c0: xy = one texel, z = far (units), w = radius of the disc (texels)
// c1: x = depth tolerance (part of the depth)
sampler AOSampler    : register(s0);
sampler DepthSampler : register(s1);
const float4 g_Params : register(c0);
const float4 g_Tol    : register(c1);

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

float depthAt(float2 uv) { return sqrt(max(tex2D(DepthSampler, uv).r, 0.0)) * g_Params.z; }

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float d0 = depthAt(uv);
	// a turn per pixel of the 4 x 4 tile: a random unit vector (no sin() in ps_2_b)
	float2 cell = floor(fmod(uv / g_Params.xy, 4.0));
	float2 cs = normalize(float2(hash(cell), hash(cell + 5.0)) * 2.0 - 1.0 + 0.0001);
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
