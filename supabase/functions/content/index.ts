// Serves published content packs to the app.
//   GET /functions/v1/content/manifest       → {"packs": {"g4": 3, ...}}
//   GET /functions/v1/content/packs/<grade>  → the grade's pack JSON
// Packs are produced by `select publish_pack('<grade>')` (see the migration).
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!);

const json = (body: unknown, status = 200, maxAge = 300) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": `public, max-age=${maxAge}` },
  });

Deno.serve(async (req) => {
  if (req.method !== "GET") return json({ error: "method not allowed" }, 405, 0);
  const path = new URL(req.url).pathname;

  if (path.endsWith("/manifest")) {
    const { data, error } = await supabase.from("content_packs").select("grade_id, version");
    if (error) return json({ error: error.message }, 500, 0);
    return json({ packs: Object.fromEntries(data.map((r) => [r.grade_id, r.version])) }, 200, 60);
  }

  const match = path.match(/\/packs\/([a-z0-9_]+)$/);
  if (match) {
    const { data, error } = await supabase.from("content_packs").select("pack").eq("grade_id", match[1]).maybeSingle();
    if (error) return json({ error: error.message }, 500, 0);
    if (!data) return json({ error: "not found" }, 404, 0);
    return json(data.pack, 200, 3600);
  }

  return json({ error: "not found" }, 404, 0);
});
