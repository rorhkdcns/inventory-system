// =====================================================================
//  Supabase Edge Function: read-shipping-photo
//  사장님 출고 사진(표)을 받아 제미나이로 읽고, JSON 배열로 돌려준다.
//
//  - 제미나이 API 키는 코드에 넣지 않고 Supabase Secrets 의 GEMINI_API_KEY 를 쓴다.
//  - (선택) Secrets 에 GEMINI_MODEL 을 넣으면 그 모델을 쓴다. 없으면 아래 기본값.
//
//  요청:  POST { image: "<base64, data: 접두어 없이>", mimeType: "image/jpeg" }
//  응답:  { items: [{ name, qty, col, can, floor }] }   또는  { error: "..." }
// =====================================================================

const DEFAULT_MODEL = "gemini-3.8-flash";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

const PROMPT = `이 사진은 창고 출고 목록(표)입니다. 표의 각 행을 읽어 JSON 배열로만 답하세요.

각 행 항목:
- name: 제품명 (사진에 적힌 그대로, 괄호·용량 표기 포함. 예: "칼라 컬러크림 (6/30) [120㎖]")
- qty: 박스 수 (숫자)
- col: 위치의 열. "A", "B", "C" 중 하나. 위치가 안 적혀 있으면 null
- can: 위치의 칸 번호(숫자). 없으면 null
- floor: 위치의 층 번호(숫자). 없으면 null

위치는 "A-2-1", "A2-1", "A열 2칸 1층" 처럼 다양하게 적힐 수 있습니다. 순서는 열-칸-층입니다.

규칙:
- 맨 아래 합계 행(제품명 없이 숫자만 있는 행)은 빼세요.
- 제목/머리글 행은 빼세요.
- 글씨가 흐려도 최대한 읽고, 읽을 수 없는 칸만 null 로 두세요.`;

const RESPONSE_SCHEMA = {
  type: "ARRAY",
  items: {
    type: "OBJECT",
    properties: {
      name: { type: "STRING" },
      qty: { type: "NUMBER" },
      col: { type: "STRING", nullable: true },
      can: { type: "INTEGER", nullable: true },
      floor: { type: "INTEGER", nullable: true },
    },
    required: ["name", "qty"],
  },
};

function toIntOrNull(v: unknown): number | null {
  const n = Number(v);
  return v === null || v === undefined || v === "" || !Number.isFinite(n) || n < 1 ? null : Math.round(n);
}

// 제미나이 결과를 앱이 쓰기 좋은 모양으로 정리
function normalize(raw: unknown) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((r: any) => {
      const name = String(r?.name ?? "").trim();
      const qty = Math.round(Number(r?.qty) * 100) / 100;
      const col = String(r?.col ?? "").trim().toUpperCase();
      return {
        name,
        qty: Number.isFinite(qty) ? qty : 0,
        col: ["A", "B", "C"].includes(col) ? col : null,
        can: toIntOrNull(r?.can),
        floor: toIntOrNull(r?.floor),
      };
    })
    .filter((r) => r.name !== "" && !/^[\d\s.,]+$/.test(r.name)); // 합계 행(숫자만) 제외
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "POST 요청만 받습니다" }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "GEMINI_API_KEY 가 Supabase Secrets 에 없습니다" }, 500);
  const model = Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL;

  let image = "";
  let mimeType = "image/jpeg";
  try {
    const body = await req.json();
    image = String(body?.image ?? "");
    if (body?.mimeType) mimeType = String(body.mimeType);
  } catch {
    return json({ error: "요청 형식이 올바르지 않습니다" }, 400);
  }
  if (!image) return json({ error: "이미지가 없습니다" }, 400);
  if (image.length > 8_000_000) return json({ error: "이미지가 너무 큽니다" }, 413);

  const geminiRes = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [
            { text: PROMPT },
            { inline_data: { mime_type: mimeType, data: image } },
          ],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA,
        },
      }),
    },
  );

  const geminiBody = await geminiRes.json().catch(() => null);
  if (!geminiRes.ok) {
    console.error("Gemini error", geminiRes.status, geminiBody);
    const msg = geminiBody?.error?.message || `HTTP ${geminiRes.status}`;
    return json({ error: `제미나이 호출 실패: ${msg}` }, 502);
  }

  const parts = geminiBody?.candidates?.[0]?.content?.parts ?? [];
  const text = parts.filter((p: any) => !p.thought && typeof p.text === "string").map((p: any) => p.text).join("");
  try {
    return json({ items: normalize(JSON.parse(text)) });
  } catch {
    console.error("Gemini 응답 파싱 실패", text);
    return json({ error: "사진에서 표를 읽지 못했습니다. 더 선명한 사진으로 다시 시도해 주세요." }, 502);
  }
});
