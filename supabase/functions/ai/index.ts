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

function nlp(body: Record<string, unknown>) {
  const text = String(body.text ?? "").toLowerCase();
  const interval = text.match(/every\s+(\d+)\s+(hour|hours|minute|minutes)/);
  const isHydration = text.includes("water") || text.includes("drink");
  const isEmergency = text.includes("emergency") || text.includes("call");

  return json({
    intent: isEmergency
      ? "call_emergency"
      : isHydration
        ? "hydration_reminder"
        : "create_reminder",
    task: isHydration ? "Drink water" : String(body.text ?? ""),
    interval: interval ? `${interval[1]} ${interval[2]}` : null,
    priority: isEmergency ? "emergency" : "normal",
    summary: isHydration
      ? "Drink water"
      : String(body.text ?? "").slice(0, 120),
    model: "gemma-2-lightweight-edge-fallback",
  });
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
