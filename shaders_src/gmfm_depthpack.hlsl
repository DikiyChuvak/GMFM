// GM:FM (b0.2.7) — packs the fog passes of the SSAO depth into one 8-bit RGBA texture (Linux /
// macOS, where no float target can be drawn into), two textures at a time: a third sampler
// ($texture2) drew nothing in some sessions there, so the packing is two steps.
//   gmfm_depthpack  — s0, s1 = the passes ending at far / 4 and far / 16 -> R, G
//   gmfm_depthpack2 — s0 = that, s1 = the pass ending at far / 64 -> R, G kept, B
// Each pass holds depth / its end, 1 at or past it. Read raw (no linear read), written raw.
sampler First  : register(s0);
sampler Second : register(s1);
// c3.xy (b0.2.7): a quarter of a texel. The depth is point sampled, and under the game's OpenGL
// layer the quad's coordinates fall on the borders between texels: a lookup there took the row
// above or below at random — rows doubled and skipped, the smoothing and the normals in steps
// (measured: row-to-row depth 0, 3, 0, 2.5 … for an even 1.4). A quarter texel in is inside the
// right one whether the coordinate sits on a border or a centre.
const float4 g_Texel : register(c3);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
#ifdef SECOND_STEP
	float2 q = uv + g_Texel.xy;
	return float4(tex2D(First, q).rg, tex2D(Second, q).r, 1);
#else
	float2 q = uv + g_Texel.xy;
	return float4(tex2D(First, q).r, tex2D(Second, q).r, 0, 1);
#endif
}
