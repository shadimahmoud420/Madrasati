// "المعلم الذكي": answers a student's question grounded on curriculum
// passages that the app retrieved from its offline content (RAG).
//
// Secrets (supabase secrets set ...): ANTHROPIC_API_KEY
// Optional: TUTOR_MODEL, TUTOR_DAILY_LIMIT (default 40 questions/student/day)
import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MODEL = Deno.env.get("TUTOR_MODEL") ?? "claude-opus-5-5";
const DAILY_LIMIT = Number(Deno.env.get("TUTOR_DAILY_LIMIT") ?? "40");

// Stable across requests so it can be cached; everything per-request goes
// in the user turn.
const SYSTEM_PROMPT = `You are "المعلم الذكي", a patient teacher inside Madrasati, a learning app for school students in Gaza (grades 1–12, Palestinian curriculum). Students may be studying alone, with interrupted schooling and limited internet.

How to answer:
- Reply in clear Modern Standard Arabic suited to the student's grade. For English-language lessons, explain in Arabic and give examples in English.
- Base your answer on the curriculum excerpts provided in <curriculum>. Use the same terms, symbols and methods as the excerpts (for example ق = ك × ت). If the excerpts don't cover the question, you may still help with general school knowledge, but say briefly that this part isn't from the app's lessons. Never invent page numbers or claim something is in the book when it isn't.
- Teach, don't just hand over answers: for a problem, show the steps and the reasoning, then invite the student to try a similar one. If the student asks to be tested, ask one question at a time and wait for their answer before giving feedback.
- Keep it short: a few short paragraphs or numbered steps; young grades get simpler words and shorter sentences. Use plain text with simple lists (no tables, no LaTeX).
- Be warm and encouraging. Students may mention hard circumstances; respond with kindness and keep the focus on learning.
- Stay on schoolwork. Politely decline unrelated or unsafe requests. Never ask for personal information (full name, address, phone, photos).`;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

type Turn = { role: "user" | "assistant"; content: string };

interface TutorRequest {
  grade?: string;
  student?: string;
  subject?: string | null;
  question?: string;
  history?: Turn[];
  context?: { title: string; text: string }[];
}

const clip = (s: unknown, max: number) => (typeof s === "string" ? s.slice(0, max) : "");

/** Alternating user/assistant turns, starting with the user. */
function cleanHistory(history: Turn[] | undefined): Anthropic.MessageParam[] {
  const out: Anthropic.MessageParam[] = [];
  for (const t of (history ?? []).slice(-8)) {
    if ((t.role !== "user" && t.role !== "assistant") || typeof t.content !== "string") continue;
    const content = clip(t.content, 4000);
    if (!content.trim()) continue;
    if (out.length === 0 && t.role !== "user") continue;
    const last = out[out.length - 1];
    if (last && last.role === t.role) {
      last.content = `${last.content}\n\n${content}`;
    } else {
      out.push({ role: t.role, content });
    }
  }
  // The new question is a user turn, so history must end with the assistant.
  if (out.length > 0 && out[out.length - 1].role === "user") out.pop();
  return out;
}

async function overDailyLimit(userId: string): Promise<boolean> {
  const day = new Date().toISOString().slice(0, 10);
  const { data } = await admin.from("tutor_usage").select("count").eq("user_id", userId).eq("day", day).maybeSingle();
  const count = data?.count ?? 0;
  if (count >= DAILY_LIMIT) return true;
  await admin.from("tutor_usage").upsert({ user_id: userId, day, count: count + 1 });
  return false;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // Requires the app's (anonymous) user session.
  const token = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const { data: auth } = await admin.auth.getUser(token);
  if (!auth?.user) return json({ error: "يجب تسجيل الدخول." }, 401);

  let body: TutorRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "طلب غير صالح." }, 400);
  }
  const question = clip(body.question, 2000).trim();
  if (!question) return json({ error: "السؤال فارغ." }, 400);

  if (await overDailyLimit(auth.user.id)) {
    return json({ error: "وصلت إلى الحد اليومي لأسئلة المعلم الذكي. عُد غدًا!" }, 429);
  }

  const passages = (body.context ?? []).slice(0, 4).map(
    (c) => `<lesson title="${clip(c.title, 200).replaceAll('"', "'")}">\n${clip(c.text, 6000)}\n</lesson>`,
  );
  const userTurn = [
    `<student grade="${clip(body.grade, 60)}"${body.subject ? ` subject="${clip(body.subject, 60)}"` : ""}/>`,
    `<curriculum>\n${passages.length ? passages.join("\n") : "(no matching lessons found in the app)"}\n</curriculum>`,
    question,
  ].join("\n\n");

  try {
    const response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      // Short tutoring answers: low effort keeps latency and cost down.
      output_config: { effort: "low" },
      // Retry a safety decline on Anthropic's recommended fallback model.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      messages: [...cleanHistory(body.history), { role: "user", content: userTurn }],
    });

    if (response.stop_reason === "refusal") {
      return json({ reply: "لا أستطيع المساعدة في هذا الطلب. اسألني عن دروسك وسأساعدك بكل سرور." });
    }
    const reply = response.content
      .flatMap((block) => (block.type === "text" ? [block.text] : []))
      .join("\n")
      .trim();
    return json({ reply: reply || "لم أتمكن من صياغة إجابة، حاول إعادة صياغة سؤالك." });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "المعلم الذكي مشغول الآن، حاول بعد دقيقة." }, 503);
    }
    if (error instanceof Anthropic.APIError) {
      console.error("Anthropic API error", error.status, error.message);
      return json({ error: "تعذّر الوصول إلى المعلم الذكي." }, 502);
    }
    console.error(error);
    return json({ error: "حدث خطأ غير متوقع." }, 500);
  }
});
