// Supabase public client configuration for to you.
// Never put a service_role key in this file.
window.TOYOU_SUPABASE_URL='https://xxeuzzgjjdumiltqqekp.supabase.co';
window.TOYOU_SUPABASE_ANON_KEY='sb_publishable_IBEr5KhQxdDC2hkEHX9kMQ_mbgAoNYg';

// Fix the connection display without changing the rest of the app.
(function(){
  function start(){
    let tries=0;
    const timer=setInterval(function(){
      tries++;

      if(typeof window.refreshPartner==='function' && window.sb && window.s){
        window.refreshPartner=async function(){
          if(!window.sb || !window.s || !window.s.auth)return;

          const {data,error}=await window.sb.rpc('get_my_connection');

          if(error || !data || !data.length){
            window.s.partner=null;
            window.s.connected=false;
          }else{
            const p=data[0];

            window.s.partner={
              id:p.partner_id,
              name:p.partner_name||'Her',
              avatar:p.partner_avatar||'',
              email:'',
              provider:''
            };

            window.s.connected=true;
          }

          if(typeof window.save==='function')window.save();
          if(typeof window.render==='function')window.render();
        };

        if(window.s.auth)window.refreshPartner();

        clearInterval(timer);
      }

      if(tries>120)clearInterval(timer);
    },250);
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded',start);
  }else{
    start();
  }
})();
