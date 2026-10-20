// Gives a golfer a LiveKit token for one round's camera stream.
// Streaming (publish) is only for the golfer who started the round while it is live;
// watching is for anyone the database lets watch (friends of a live round, or players in it).
//
// Deploy:  supabase functions deploy livekit-token
// Secrets: supabase secrets set LIVEKIT_URL=wss://<project>.livekit.cloud LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { AccessToken } from "npm:livekit-server-sdk@2.6.1";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Sign in first" }, 401);

  // Acts as the caller, so row-level security decides what they can see.
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "Sign in first" }, 401);

  const { round_id, publish } = await req.json();
  if (typeof round_id !== "string") return json({ error: "round_id is required" }, 400);

  const { data: round } = await supabase
    .from("rounds")
    .select("id, created_by, live, finished_at")
    .eq("id", round_id)
    .maybeSingle();
  if (!round) return json({ error: "You can't watch this round" }, 403);
  if (!round.live || round.finished_at) return json({ error: "This round isn't live" }, 409);
  if (publish && round.created_by !== user.id) return json({ error: "Only the golfer who went live can stream" }, 403);

  const token = new AccessToken(Deno.env.get("LIVEKIT_API_KEY")!, Deno.env.get("LIVEKIT_API_SECRET")!, {
    identity: user.id,
    ttl: "4h",
  });
  token.addGrant({
    room: `round-${round.id}`,
    roomJoin: true,
    canPublish: Boolean(publish),
    canPublishData: false,
    canSubscribe: true,
  });
  return json({ url: Deno.env.get("LIVEKIT_URL"), token: await token.toJwt() });
});
