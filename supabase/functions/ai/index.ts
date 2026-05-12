import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const action = body.action as string;

    if (action === "transcribe") return transcribe(body);
    if (action === "nlp") return nlp(body);
    if (action === "translate") return translate(body);
    if (action === "tts") return tts(body);

    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});

async function transcribe(body: Record<string, unknown>) {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json({ text: "", usedFallback: true });

  const audioBytes = body.audioBase64 as number[] | undefined;
  const fileName = (body.fileName as string | undefined) ?? "audio.webm";
  const language = (body.languageHint as string | undefined) ?? "en";
  if (!audioBytes) return json({ text: "", usedFallback: true });

  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("language", language);
  form.append("file", new Blob([new Uint8Array(audioBytes)]), fileName);

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  const data = await response.json();
  return json({ text: data.text ?? "", language });
}

async function nlp(body: Record<string, unknown>) {
  const gemmaResult = await parseWithGemma(body);
  if (gemmaResult) return json(gemmaResult);

  const text = String(body.text ?? "").toLowerCase();
  const interval = text.match(/every\s+(\d+)\s+(hour|hours|minute|minutes)/);
  const isHydration = text.includes("water") || text.includes("drink");
  const isEmergency = text.includes("emergency") || text.includes("call");
  const isTranslate = text.includes("translate") ||
    text.includes("tagalog") ||
    text.includes("english");
  const isSummary = text.includes("summarize") || text.includes("summary");

  let intent = "create_reminder";
  if (isEmergency) intent = "call_emergency";
  if (isTranslate) intent = "translate";
  if (isSummary) intent = "summarize";

  return json({
    intent,
    task: isHydration ? "Drink water" : String(body.text ?? ""),
    repeat: interval ? `${interval[1]} ${interval[2]}` : null,
    time: extractTime(text),
    priority: isEmergency ? "emergency" : "normal",
    summary: isHydration
      ? "Drink water"
      : String(body.text ?? "").slice(0, 120),
    confidence: isEmergency || isHydration || isTranslate || isSummary
      ? 0.76
      : 0.55,
    model: "gemma-2-lightweight-edge-fallback",
    usedFallback: true,
  });
}

async function parseWithGemma(body: Record<string, unknown>) {
  const endpoint = Deno.env.get("GEMMA_API_URL");
  const apiKey = Deno.env.get("GEMMA_API_KEY");
  const model = Deno.env.get("GEMMA_MODEL") ?? "google/gemma-2-2b-it";
  const text = String(body.text ?? "").trim();
  if (!endpoint || !apiKey || !text) return null;

  const prompt = [
    "You are the LifeEase PH voice command parser.",
    "Recognize English, Tagalog, and mixed English-Tagalog commands.",
    "Return only valid JSON with these keys:",
    "intent, task, summary, time, repeat, confidence, language.",
    "Allowed intents: create_reminder, call_emergency, translate, summarize, unknown.",
    "Use null for missing time or repeat. Confidence must be 0 to 1.",
    `User text: ${JSON.stringify(text)}`,
  ].join("\n");

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
        temperature: 0.1,
        max_tokens: 220,
      }),
    });

    if (!response.ok) return null;
    const data = await response.json();
    const content = extractModelContent(data);
    const parsed = parseJsonObject(content);
    if (!parsed) return null;

    return {
      intent: normalizeIntent(parsed.intent),
      task: stringOrNull(parsed.task) ?? text,
      summary: stringOrNull(parsed.summary) ?? text.slice(0, 120),
      time: stringOrNull(parsed.time),
      repeat: stringOrNull(parsed.repeat),
      confidence: numberOrDefault(parsed.confidence, 0.75),
      language: stringOrNull(parsed.language) ?? "unknown",
      model,
      usedFallback: false,
    };
  } catch (_) {
    return null;
  }
}

function extractModelContent(data: Record<string, unknown>) {
  const choices = data.choices as Array<Record<string, unknown>> | undefined;
  const first = choices?.[0];
  const message = first?.message as Record<string, unknown> | undefined;
  const content = message?.content ?? first?.text ?? data.generated_text;
  return typeof content === "string" ? content : "";
}

function parseJsonObject(content: string) {
  const trimmed = content.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1];
  const candidate = fenced ?? trimmed;
  const objectMatch = candidate.match(/\{[\s\S]*\}/);
  if (!objectMatch) return null;

  try {
    return JSON.parse(objectMatch[0]) as Record<string, unknown>;
  } catch (_) {
    return null;
  }
}

function normalizeIntent(value: unknown) {
  const intent = String(value ?? "unknown").toLowerCase();
  if (
    intent === "create_reminder" ||
    intent === "call_emergency" ||
    intent === "translate" ||
    intent === "summarize"
  ) {
    return intent;
  }
  if (intent === "add_reminder" || intent === "hydration_reminder") {
    return "create_reminder";
  }
  return "unknown";
}

function stringOrNull(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || trimmed.toLowerCase() === "null") return null;
  return trimmed;
}

function numberOrDefault(value: unknown, fallback: number) {
  if (typeof value !== "number" || Number.isNaN(value)) return fallback;
  return Math.max(0, Math.min(1, value));
}

function extractTime(text: string) {
  const match = text.match(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/);
  if (!match) return null;
  const minute = match[2] ?? "00";
  return `${match[1]}:${minute.padStart(2, "0")} ${match[3].toUpperCase()}`;
}

async function translate(body: Record<string, unknown>) {
  const apiKey = Deno.env.get("GOOGLE_TRANSLATE_API_KEY");
  if (!apiKey) return json({ text: body.text, usedFallback: true });

  const response = await fetch(
    `https://translation.googleapis.com/language/translate/v2?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        q: body.text,
        target: body.targetLanguage,
        source: body.sourceLanguage === "mixed" ? undefined : body.sourceLanguage,
        format: "text",
      }),
    },
  );
  const data = await response.json();
  return json({
    text: data.data?.translations?.[0]?.translatedText ?? body.text,
  });
}

async function tts(body: Record<string, unknown>) {
  const apiKey = Deno.env.get("INWORLD_API_KEY");
  const endpoint = Deno.env.get("INWORLD_TTS_URL");
  if (!apiKey || !endpoint) {
    return json({ audioBytes: null, usedFallback: true });
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: body.text,
      speaking_rate: body.speed ?? 0.95,
      volume_gain: body.volume ?? 1,
      voice: "friendly_elder_child_safe",
    }),
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  return json({ audioBytes: Array.from(bytes) });
}

function json(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
