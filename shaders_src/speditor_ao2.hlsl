// SPeditor — screen space ambient occlusion from a linear depth texture.
// s0: depth from SPeditor's depth pass: R = (view depth / far)^2 (the fog is blended in gamma
//     space, measured in game); 1 = sky / nothing
// c0: x = radius (units), y = strength, z = far (units), w = bias
// c1: x = tan(half horizontal fov), y = tan(half vertical fov), z = 1 / width, w = 1 / height
// Output: R = G = B = visibility (1 = open, 0 = fully occluded).
sampler DepthSampler : register(s0);
const float4 g_Params : register(c0);
const float4 g_View   : register(c1);

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

#define SAMPLES 12

float3 viewPos(float2 uv)
{
	// max(): the blended value can come out a hair below zero next to the camera, and the
	// square root of it is NaN — a NaN pixel came out white and the whole frame lost its AO
	float d = sqrt(max(rawDepth(uv), 0.0)) * g_Params.z;
	float2 ndc = uv * float2(2.0, -2.0) + float2(-1.0, 1.0);
	return float3(ndc.x * g_View.x * d, ndc.y * g_View.y * d, d);
}

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	// No early return or if: the compiler made a real branch of it (ifc), and the Linux game's
	// D3D -> OpenGL translation (ToGL) stopped the game with "GLSL translation error" on this
	// shader — the branch is the suspect. The sky is kept open by a select at the end instead.
	float depth = rawDepth(uv);
	float3 p = viewPos(uv);

	// the normal from the nearer neighbour on each axis (keeps edges clean)
	float3 pr = viewPos(uv + float2(g_View.z * NORMAL_STEP, 0));
	float3 pl = viewPos(uv - float2(g_View.z * NORMAL_STEP, 0));
	float3 pd = viewPos(uv + float2(0, g_View.w * NORMAL_STEP));
	float3 pu = viewPos(uv - float2(0, g_View.w * NORMAL_STEP));
	float3 dx = (abs(pr.z - p.z) < abs(p.z - pl.z)) ? (pr - p) : (p - pl);
	float3 dy = (abs(pd.z - p.z) < abs(p.z - pu.z)) ? (pd - p) : (p - pu);
	float3 nc = cross(dy, dx);
	float cl = length(nc);
	float3 n = (cl > 1e-6) ? nc / cl : float3(0, 0, -1);
	n = (n.z > 0) ? -n : n;  // towards the camera

	// the radius on screen; a per-pixel turn of the pattern (the blur removes the noise)
	float2 px = uv / float2(g_View.z, g_View.w);
	float h1 = frac(52.9829189 * frac(dot(px, float2(0.06711056, 0.00583715))));
	float h2 = frac(52.9829189 * frac(dot(px.yx, float2(0.06711056, 0.00583715)) + 0.37));
	float2 cs = normalize(float2(h1, h2) * 2.0 - 1.0 + 0.0001);
	float c = cs.x, s = cs.y;
	float2 rad = g_Params.x / max(p.z, 1.0) / float2(2.0 * g_View.x, 2.0 * g_View.y);

	float occ = 0;
	[unroll] for (int i = 0; i < SAMPLES; i++)
	{
		// a spiral of SAMPLES points filling the disc
		float t = (i + 0.5) / SAMPLES;
		float a = i * 2.39996323;
		float2 o = float2(cos(a), sin(a)) * sqrt(t);
		o = float2(o.x * c - o.y * s, o.x * s + o.y * c);
		float2 su = uv + o * rad;
		float3 q = viewPos(su);
		float3 v = q - p;
		float dist = length(v);
		// a point off the frame is unknown: counted as open (it darkened the frame edges)
		float2 inside = step(0.0, su) * step(su, 1.0);
		float fall = saturate(1.0 - dist / (g_Params.x * 1.5)) * inside.x * inside.y;
		// packed depth (b0.2.7): what rises less than a step of the depth off the surface is not counted
		occ += saturate(dot(n, v / max(dist, 0.001)) - g_Params.w - 0.5 * quantStep(q.z, g_Params.z) / max(dist, 0.001)) * fall;
	}
	float vis = saturate(1.0 - g_Params.y * occ / SAMPLES * 2.0);
	vis = (vis == vis) ? vis : 1.0;      // NaN: leave the pixel open
	vis = (depth > 0.999) ? 1.0 : vis;   // sky / nothing: open
	return float4(vis, vis, vis, 1);
}
