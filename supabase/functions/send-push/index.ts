import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY")!;
const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY")!;
const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:notifications@toyou.app";
const cronToken = Deno.env.get("CRON_PUSH_TOKEN") || "";

const admin = createClient(supabaseUrl, serviceRole);
webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);

function cors(body: unknown, status=200){
  return new Response(JSON.stringify(body),{
    status,
    headers:{"content-type":"application/json","access-control-allow-origin":"*","access-control-allow-headers":"authorization,apikey,content-type,x-cron-token"}
  });
}

async function userFromJwt(req: Request){
  const auth=req.headers.get("authorization")||"";
  if(!auth.toLowerCase().startsWith("bearer "))return null;
  const token=auth.slice(7);
  const {data}=await admin.auth.getUser(token);
  return data.user||null;
}

async function sendToUser(userId:string,title:string,body:string,tag:string){
  const {data:subs}=await admin.from("push_subscriptions").select("id,endpoint,p256dh,auth").eq("user_id",userId);
  let sent=0,removed=0;
  for(const sub of subs||[]){
    try{
      await webpush.sendNotification(
        {endpoint:sub.endpoint,keys:{p256dh:sub.p256dh,auth:sub.auth}},
        JSON.stringify({title,body,tag,icon:"./icon.svg",badge:"./icon.svg"})
      );
      sent++;
    }catch(e){
      const status=(e as {statusCode?:number})?.statusCode;
      if(status===404||status===410){
        await admin.from("push_subscriptions").delete().eq("id",sub.id);
        removed++;
      }
    }
  }
  return {sent,removed};
}

async function sendDue(){
  const now=new Date();
  const {data:rows,error}=await admin.from("notification_schedules")
    .select("id,user_id,title,body,notify_at,repeat_daily,repeat_yearly")
    .eq("enabled",true)
    .lte("notify_at",now.toISOString())
    .order("notify_at",{ascending:true})
    .limit(200);
  if(error)throw error;
  let sent=0;
  for(const row of rows||[]){
    await sendToUser(row.user_id,row.title,row.body,"to-you-schedule-"+row.id);
    sent++;
    if(row.repeat_daily){
      const next=new Date(row.notify_at);
      next.setUTCDate(next.getUTCDate()+1);
      await admin.from("notification_schedules").update({notify_at:next.toISOString(),last_sent_at:now.toISOString(),updated_at:now.toISOString()}).eq("id",row.id);
    }else if(row.repeat_yearly){
      const next=new Date(row.notify_at);
      next.setUTCFullYear(next.getUTCFullYear()+1);
      await admin.from("notification_schedules").update({notify_at:next.toISOString(),last_sent_at:now.toISOString(),updated_at:now.toISOString()}).eq("id",row.id);
    }else{
      await admin.from("notification_schedules").update({enabled:false,last_sent_at:now.toISOString(),updated_at:now.toISOString()}).eq("id",row.id);
    }
  }
  return {processed:rows?.length||0,sent};
}

Deno.serve(async req=>{
  try{
    if(req.method!=="POST")return cors({error:"POST only"},405);
    const internal=req.headers.get("x-cron-token");
    if(internal && cronToken && internal===cronToken){
      return cors({ok:true,mode:"cron",...(await sendDue())});
    }
    const user=await userFromJwt(req);
    if(!user)return cors({error:"Unauthorized"},401);
    const payload=await req.json().catch(()=>({}));
    if(payload.type==="need_you"){
      const recipientId=String(payload.recipient_id||"");
      if(!recipientId)return cors({error:"recipient_id required"},400);
      const {data:couple}=await admin.from("couple_members").select("couple_id").eq("user_id",user.id);
      const coupleIds=(couple||[]).map(x=>x.couple_id);
      const {data:recipient}=await admin.from("couple_members").select("couple_id").eq("user_id",recipientId).in("couple_id",coupleIds).limit(1).maybeSingle();
      if(!recipient)return cors({error:"Recipient is not connected to this user"},403);
      return cors({ok:true,mode:"need_you",...(await sendToUser(recipientId,"I Need You",payload.message||"You received an I Need You signal.","to-you-need-you"))});
    }
    if(payload.type==="test"){
      return cors({ok:true,mode:"test",...(await sendToUser(user.id,"to you","Push notifications are working.","to-you-test"))});
    }
    return cors({error:"Unknown notification type"},400);
  }catch(e){
    return cors({error:String((e as Error)?.message||e)},500);
  }
});
