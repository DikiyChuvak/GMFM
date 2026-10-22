// GM:FM (b0.2 round 6) — film grain for the FX clips of the timeline, after the idea of SFM's
// HSL film grain: a noise of its own every frame, laid on the brightness, strongest in the
// mid tones (the darkest and the brightest parts of film keep less grain).
// s0: the frame
// c0: x = amount (0 … 1), y = grain size (pixels), z = seed (changes every frame), w = 1 — colour grain
// c1: zw = 1 / width, 1 / height
sampler FrameSampler : register(s0);
const float4 g_Grain : register(c0);
const float4 g_Size  : register(c1);

// a hash without sin(): the sin() one lost its precision on big pixel numbers and drew
// vertical streaks (Dave Hoskins' hash12)
float hash(float2 p)
{
	float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return frac((p3.x + p3.y) * p3.z);
}

// smooth noise: the four cells around the pixel, blended
float noise(float2 p, float seed)
{
	float2 i = floor(p);
	float2 f = frac(p);
	f = f * f * (3.0 - 2.0 * f);
	float2 o = float2(seed * 13.7, seed * 7.3);
	float a = hash(i + o), b = hash(i + float2(1, 0) + o);
	float c = hash(i + float2(0, 1) + o), d = hash(i + float2(1, 1) + o);
	return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float4 main(float2 uvIn : TEXCOORD0, float2 vpos : VPOS) : COLOR
{
	float2 uv = (vpos + 0.5) * g_Size.zw;
	float3 col = tex2Dlod(FrameSampler, float4(uv, 0, 0)).rgb;
	float2 p = vpos / max(g_Grain.y, 1.0);
	float seed = g_Grain.z;
	float n = noise(p, seed) - 0.5;
	float3 g = float3(n, n, n);
	if (g_Grain.w > 0.5)
		g = float3(n, noise(p, seed + 17.31) - 0.5, noise(p, seed + 41.77) - 0.5);
	float lum = dot(col, float3(0.299, 0.587, 0.114));
	float mid = 4.0 * lum * (1.0 - lum);
	col = saturate(col + g * g_Grain.x * (0.3 + 0.7 * mid));
	return float4(col, 1);
}
