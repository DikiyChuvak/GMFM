// GM:FM (b0.2) — the vertex shader of the ps30 screen passes: the quad of DrawScreenQuad
// through the engine's view projection (c8..c11), as screenspace_general's own does.
const float4 cViewProj0 : register(c8);
const float4 cViewProj1 : register(c9);
const float4 cViewProj2 : register(c10);
const float4 cViewProj3 : register(c11);

struct VS_OUT { float4 pos : POSITION; float2 uv : TEXCOORD0; };

VS_OUT main(float4 pos : POSITION, float2 uv : TEXCOORD0)
{
	VS_OUT o;
	o.pos = float4(dot(pos, cViewProj0), dot(pos, cViewProj1), dot(pos, cViewProj2), dot(pos, cViewProj3));
	o.uv = uv;
	return o;
}
