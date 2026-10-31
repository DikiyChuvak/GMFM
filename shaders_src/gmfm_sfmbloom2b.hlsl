// GM:FM (b0.2.6) — SFM's bloom (bloomScale / bloomWidth of a camera), Shader Model 2. SFM blurs
// its linear frame with a Gaussian (sfm_blurfilterx / y, sigma = bloomWidth) and adds it,
// times bloomScale (sfm_integercombine), before the frame goes to the screen's gamma. The game's
// frame is already in gamma, so this one goes through linear light the same way:
//   c0.x = 0: the frame into linear light (the copy that is blurred);
//   c0.x = 1: the frame and the blurred copy added in linear light, back into gamma.
// s0: the frame, s1: the blurred linear copy
// c0: x = the step (0 / 1), y = bloomScale
sampler FrameSampler : register(s0);
sampler BlurSampler  : register(s1);
const float4 g_Params : register(c0);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float3 f = tex2D(FrameSampler, uv).rgb;
	float3 lin = pow(max(f, 0.0), 2.2);
	float3 b = tex2D(BlurSampler, uv).rgb;
	float3 sum = pow(lin + g_Params.y * b, 1.0 / 2.2);
	return float4(lerp(lin, sum, g_Params.x), 1);
}
