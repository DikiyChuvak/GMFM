// GM:FM (b0.2.1) — the Shader Model 2 (ps_2_b) form for DirectX level 90 (texture coordinates
// instead of VPOS). Otherwise the same: colour correction for the FX clips of the timeline (as SFM's Color
// Correction clip): brightness, contrast, saturation and a tint, mixed with the frame.
// s0: the frame
// c0: x = brightness (-1 … 1), y = contrast (0 … 2), z = saturation (0 … 2), w = mix (0 … 1)
// c1: rgb = tint colour (0 … 1), w = tint amount (0 … 1)
// c2: zw = 1 / width, 1 / height
sampler FrameSampler : register(s0);
const float4 g_CC   : register(c0);
const float4 g_Tint : register(c1);
const float4 g_Size : register(c2);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float2 vpos = uv / g_Size.zw - 0.5;
	float3 src = tex2D(FrameSampler, uv).rgb;
	float3 col = (src - 0.5) * g_CC.y + 0.5 + g_CC.x;
	float lum = dot(col, float3(0.299, 0.587, 0.114));
	col = lerp(float3(lum, lum, lum), col, g_CC.z);
	// the tint keeps the brightness: white changes nothing
	float tl = max(dot(g_Tint.rgb, float3(0.299, 0.587, 0.114)), 0.001);
	col = lerp(col, col * g_Tint.rgb / tl, g_Tint.w);
	return float4(lerp(src, saturate(col), g_CC.w), 1);
}
