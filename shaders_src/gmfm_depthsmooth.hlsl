// GM:FM (b0.2.7) — smooths the packed 8-bit SSAO depth of Linux / macOS (no float targets there)
// into 16 bits. The fog passes give the depth in steps (2 units at 300 units away): a flat wall
// came out as a staircase of plateaus ~12 pixels tall, and the occlusion read every step as a
// ledge — horizontal stripes. Each pass averages 15 pixels along one axis, only those within three
// steps of the middle one (a silhouette stays sharp), so the stairs become the ramp they stand for.
// b0.2.7: the window is taken in pairs (see main).
// SPLIT_IN: the input is this shader's own output (R = high byte, G = low byte of depth / far);
// otherwise the packed bands (R = 4 d / far, G = 16 d / far, B = 64 d / far, each stopping at 1).
// Output: R = high byte, G = low byte of depth / far (1 = sky / past the last band).
// c0: xy = the step to the next pixel along the axis, z = far (units)
sampler DepthSampler : register(s0);
const float4 g_Params : register(c0);
// c3.xy (b0.2.7): a quarter of a texel. The depth is point sampled, and under the game's OpenGL
// layer the quad's coordinates fall on the borders between texels: a lookup there took the row
// above or below at random — rows doubled and skipped, the smoothing and the normals in steps
// (measured: row-to-row depth 0, 3, 0, 2.5 … for an even 1.4). A quarter texel in is inside the
// right one whether the coordinate sits on a border or a centre.
const float4 g_Texel : register(c3);

float depthOf(float2 uv)
{
	float3 t = tex2D(DepthSampler, uv + g_Texel.xy).rgb;
#ifdef SPLIT_IN
	return t.r + t.g / 255.0;
#else
	// the finest pass below 90 % of its range: a pass at its end reads a little under 1 when the game
	// dims the fog (250 for 255 measured on gm_construct), so "at its end" is not "1" (b0.2.7)
	float d = (t.r < 0.9) ? t.r / 4.0 : 1.0;
	d = (t.g < 0.9) ? t.g / 16.0 : d;
	d = (t.b < 0.9) ? t.b / 64.0 : d;
	return d;
#endif
}

float stepOf(float d)    // one step of the packed depth at d (a part of far)
{
	return (d < 0.9 / 64.0) ? 1.0 / (64.0 * 255.0) : ((d < 0.9 / 16.0) ? 1.0 / (16.0 * 255.0) : 1.0 / (4.0 * 255.0));
}

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float d0 = depthOf(uv);
	float tol = 3.0 * stepOf(d0);
	float sum = d0, wsum = 1.0;
	// the pixels at the same distance on both sides are taken together, and the window ends at the
	// first pair of which one is past an edge: the window stays even. Taken one by one within a
	// tolerance of the middle value, the window was even in depth, not in place — on a staircase
	// it took the same steps above as below, and the mean was the middle step again: no smoothing
	// at all (measured on a drawn staircase: the output the input, row for row)
	float open = 1.0;
	[unroll] for (int i = 1; i <= 7; i++)
	{
		float a = depthOf(uv + g_Params.xy * i);
		float b = depthOf(uv - g_Params.xy * i);
		float w = ((abs(a - d0) <= tol) ? 1.0 : 0.0) * ((abs(b - d0) <= tol) ? 1.0 : 0.0);
		open *= w;
		sum += (a + b) * open;
		wsum += 2.0 * open;
	}
	float d = sum / wsum;
	d = (d0 >= 0.999) ? 1.0 : d;     // the sky stays the sky
	float hi = floor(d * 255.0) / 255.0;
	float lo = frac(d * 255.0);
	return float4(hi, lo, 0, 1);
}
