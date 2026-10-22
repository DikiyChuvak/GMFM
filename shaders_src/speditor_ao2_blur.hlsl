// SPeditor — depth-aware blur of the occlusion along one direction.
// s0: occlusion, s1: depth (as in speditor_ao.hlsl)
// c0: xy = one texel along the blur direction, z = far (units), w = depth tolerance (units)
sampler AOSampler    : register(s0);
sampler DepthSampler : register(s1);
const float4 g_Params : register(c0);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float d0 = sqrt(max(tex2D(DepthSampler, uv).r, 0.0)) * g_Params.z;
	float sum = 0, wsum = 0;
	[unroll] for (int i = -4; i <= 4; i++)
	{
		float2 q = uv + g_Params.xy * i;
		float d = sqrt(max(tex2D(DepthSampler, q).r, 0.0)) * g_Params.z;
		float w = (5.0 - abs(i)) * saturate(1.0 - abs(d - d0) / (g_Params.w * max(d0, 1.0) * 0.01 + 0.5));
		sum += tex2D(AOSampler, q).r * w;
		wsum += w;
	}
	float v = sum / max(wsum, 0.0001);
	return float4(v, v, v, 1);
}
