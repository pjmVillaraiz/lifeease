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
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) return json({ text: "", usedFallback: true });

  const audioBytes = body.audioBase64 as number[] | undefined;
  const fileName = (body.fileName as string | undefined) ?? "audio.webm";
  const language = (body.languageHint as string | undefined) ?? "en";
  if (!audioBytes) return json({ text: "", usedFallback: true });

  const form = new FormData();
  const sttModel = Deno.env.get("GROQ_STT_MODEL") ?? "whisper-large-v3-turbo";
  form.append("model", sttModel);
  form.append("response_format", "json");
  form.append("temperature", "0");
  if (language === "en" || language === "tl") {
    form.append("language", language);
  }
  form.append("file", new Blob([new Uint8Array(audioBytes)]), fileName);

  const response = await fetch(
    "https://api.groq.com/openai/v1/audio/transcriptions",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    },
  );
  if (!response.ok) {
    return json({
      text: "",
      language,
      usedFallback: true,
      error: await safeError(response),
    });
  }
  const data = await response.json();
  return json({ text: data.text ?? "", language, model: sttModel });
}

async function nlp(body: Record<string, unknown>) {
  const gemmaResult = await parseWithGemma(body);
  if (gemmaResult) return json(gemmaResult);

  const text = String(body.text ?? "").toLowerCase();
  const interval = text.match(/every\s+(\d+)\s+(hour|hours|minute|minutes)/);
  const isHydration = text.includes("water") || text.includes("drink") ||
    text.includes("tubig") || text.includes("uminom");
  const isEmergency = text.includes("emergency") || text.includes("call") ||
    text.includes("tawag");
  const isTranslate = text.includes("translate") ||
    text.includes("tagalog") ||
    text.includes("english") ||
    text.includes("isalin");
  const isSummary = text.includes("summarize") || text.includes("summary");
  const isReminderList = text.includes("show my reminders") ||
    text.includes("mga paalala") ||
    text.includes("list reminders");
  const isSchedule = text.includes("today schedule") ||
    text.includes("daily schedule") ||
    text.includes("iskedyul");
  const isStats = text.includes("statistics") || text.includes("ulat");
  const isInternet = text.includes("weather") || text.includes("panahon") ||
    text.includes("what time") || text.includes("anong oras");

  let intent = "create_reminder";
  if (isEmergency) intent = "call_emergency";
  if (isTranslate) intent = "translate";
  if (isSummary) intent = "summarize";
  if (isReminderList) intent = "reminder_list";
  if (isSchedule) intent = "daily_schedule";
  if (isStats) intent = "statistics";
  if (isInternet) intent = "internet_query";

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
  const apiKey = Deno.env.get("GEMINI_API_KEY") ?? Deno.env.get("GEMMA_API_KEY");
  const model = Deno.env.get("GEMMA_MODEL") ?? "gemma-2-2b-it";
  const text = String(body.text ?? "").trim();
  if (!apiKey || !text) return null;

  const prompt = [
    "You are the LifeEase PH voice command parser powered by Gemma 2.",
    "Recognize English, Tagalog, and mixed English-Tagalog spoken commands.",
    "Summarize the command in one short sentence (max 90 characters).",
    "Return only valid JSON with these keys:",
    "intent, task, summary, time, repeat, confidence, language.",
    "Allowed intents:",
    "create_reminder, call_emergency, translate, summarize,",
    "reminder_list, daily_schedule, navigation, statistics,",
    "internet_query, unknown.",
    "task: the core action or reminder title (e.g. Take medicine, Uminom ng gamot).",
    "time: 12-hour format like 8:00 AM when mentioned, else null.",
    "repeat: daily, weekly, monthly, or null.",
    "confidence: number from 0 to 1.",
    "language: en, tl, mixed, or unknown.",
    `User text: ${JSON.stringify(text)}`,
  ].join("\n");

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: {
          "x-goog-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          contents: [{
            role: "user",
            parts: [{ text: prompt }],
          }],
          generationConfig: {
            temperature: 0.1,
            maxOutputTokens: 220,
            responseMimeType: "application/json",
          },
        }),
      },
    );

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
  const candidates = data.candidates as
    | Array<Record<string, unknown>>
    | undefined;
  const firstCandidate = candidates?.[0];
  const candidateContent = firstCandidate?.content as
    | Record<string, unknown>
    | undefined;
  const parts = candidateContent?.parts as
    | Array<Record<string, unknown>>
    | undefined;
  const firstText = parts
    ?.map((part) => part.text)
    .find((text) => typeof text === "string");
  if (typeof firstText === "string") return firstText;

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
  const allowed = new Set([
    "create_reminder",
    "call_emergency",
    "translate",
    "summarize",
    "reminder_list",
    "daily_schedule",
    "navigation",
    "statistics",
    "internet_query",
    "unknown",
  ]);
  if (allowed.has(intent)) return intent;
  if (intent === "add_reminder" || intent === "hydration_reminder") {
    return "create_reminder";
  }
  if (intent === "emergency") return "call_emergency";
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
  const apiKey = Deno.env.get("CLOUDTRANSLATION_API_KEY") ??
    Deno.env.get("GOOGLE_TRANSLATE_API_KEY") ??
    Deno.env.get("GOOGLE_CLOUD_TRANSLATION_API_KEY");
  if (!apiKey) return json({ text: body.text, usedFallback: true });

  const response = await fetch(
    `https://translation.googleapis.com/language/translate/v2?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        q: body.text,
        target: body.targetLanguage,
        source: body.sourceLanguage === "mixed"
          ? undefined
          : body.sourceLanguage,
        format: "text",
      }),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    return json({
      text: body.text,
      usedFallback: true,
      error: data.error?.message ?? "Translation request failed",
    });
  }
  return json({
    text: data.data?.translations?.[0]?.translatedText ?? body.text,
  });
}

async function tts(body: Record<string, unknown>) {
  const apiKey = Deno.env.get("INWORLD_API_KEY");
  const endpoint = Deno.env.get("INWORLD_TTS_URL") ??
    "https://api.inworld.ai/tts/v1/voice";
  if (!apiKey) {
    return json({ audioBytes: null, usedFallback: true });
  }

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Basic ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: body.text,
      voiceId: Deno.env.get("INWORLD_VOICE_ID") ?? "Celeste",
      modelId: Deno.env.get("INWORLD_TTS_MODEL") ?? "inworld-tts-2",
      audioConfig: {
        audioEncoding: Deno.env.get("INWORLD_AUDIO_ENCODING") ?? "MP3",
        sampleRateHertz: Number(
          Deno.env.get("INWORLD_SAMPLE_RATE_HERTZ") ?? 22050,
        ),
        language: body.language ?? undefined,
      },
      deliveryMode: Deno.env.get("INWORLD_DELIVERY_MODE") ?? "BALANCED",
      applyTextNormalization: "ON",
    }),
  });
  const data = await response.json();
  if (!response.ok || typeof data.audioContent !== "string") {
    return json({
      audioBytes: null,
      usedFallback: true,
      error: data.error?.message ?? "TTS request failed",
    });
  }
  const bytes = base64ToBytes(data.audioContent);
  return json({ audioBytes: Array.from(bytes) });
}

async function safeError(response: Response) {
  try {
    const data = await response.json();
    return data.error?.message ?? data.error ?? response.statusText;
  } catch (_) {
    return response.statusText;
  }
}

function base64ToBytes(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function json(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
