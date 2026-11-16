#include "portal.h"
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <ArduinoJson.h>

static WebServer server(80);
static DNSServer dns;
static Settings* S = nullptr;
static bool apOpen = false;
static bool saved = false, savedWiFi = false, savedAccount = false, restartWanted = false;
static PortalStatus lastStatus;
static const char* AP_NAME = "Vox Desk";

// The page. Same look as the app: dark glass, one ice blue accent. Values are filled in by /state.
static const char PAGE[] PROGMEM = R"HTML(<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Vox Desk</title>
<style>
:root{--a:#8CD9FF;--t2:rgba(255,255,255,.6);--line:rgba(255,255,255,.12)}
*{box-sizing:border-box}body{margin:0;font-family:Inter,-apple-system,system-ui,sans-serif;color:#fff;background:linear-gradient(160deg,#0f1a2b,#0b1018 60%,#1a1410);min-height:100vh;padding:16px}
main{max-width:460px;margin:0 auto}h1{font-size:32px;margin:12px 0 2px;letter-spacing:-.02em}h1 b{color:var(--a);text-shadow:0 0 22px rgba(140,217,255,.6)}
.sub{color:var(--t2);margin:0 0 18px;font-size:14px}
.card{background:rgba(0,0,0,.38);border:1px solid var(--line);border-radius:20px;padding:18px;margin-bottom:14px;backdrop-filter:blur(20px)}
h2{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--t2);margin:0 0 12px}
label{display:block;font-size:13px;color:var(--t2);margin:10px 0 5px}
input,select{width:100%;font:inherit;color:#fff;background:rgba(255,255,255,.08);border:1px solid var(--line);border-radius:12px;padding:10px 12px;outline:none;color-scheme:dark}
input:focus,select:focus{border-color:var(--a)}select option{background:#141a22}
.row{display:flex;gap:8px;align-items:end}.row>*{flex:1}.row button{flex:0 0 auto}
button{font:inherit;font-weight:600;border:0;border-radius:999px;padding:11px 18px;cursor:pointer;background:rgba(255,255,255,.12);color:#fff}
button.p{background:var(--a);color:#0A1724;box-shadow:0 0 22px rgba(140,217,255,.35);width:100%;margin-top:6px}
.chk{display:flex;align-items:center;gap:10px;padding:8px 0;border-top:1px solid var(--line);font-size:15px}.chk:first-of-type{border-top:0}
.chk input{width:20px;height:20px;accent-color:var(--a);margin:0}.chk span{flex:1}.chk select{width:auto}
input[type=range]{padding:0;height:4px;appearance:none;background:rgba(255,255,255,.2);border:0}input[type=range]::-webkit-slider-thumb{appearance:none;width:22px;height:22px;border-radius:50%;background:#fff}
.st{display:flex;justify-content:space-between;padding:6px 0;font-size:14px;border-top:1px solid var(--line)}.st:first-of-type{border-top:0}.st b{font-weight:500;color:var(--t2)}
.ok{color:#8CD1B3}.bad{color:#FF8C85}
#msg{position:fixed;left:50%;bottom:20px;transform:translateX(-50%);background:#8CD9FF;color:#0A1724;padding:10px 18px;border-radius:999px;font-weight:600;opacity:0;transition:.3s;pointer-events:none}#msg.on{opacity:1}
.hint{font-size:12px;color:var(--t2);margin-top:6px}
.hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}.hd h2{margin:0}
button.sm{padding:7px 14px;font-size:13px}
.net{display:flex;align-items:center;gap:12px;width:100%;text-align:left;background:none;border-radius:12px;padding:12px 10px;font-weight:500;border-top:1px solid var(--line)}
.net:first-child{border-top:0}.net:hover{background:rgba(255,255,255,.06)}
.net.on{background:rgba(140,217,255,.14);color:var(--a)}
.net .n{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bars{display:inline-flex;align-items:flex-end;gap:2px;height:14px}.bars i{width:3px;background:rgba(255,255,255,.25);border-radius:1px}.bars i.f{background:currentColor}
.lock{font-size:12px;opacity:.6}
</style></head><body><main>
<h1>Vo<b>x</b> Desk</h1><p class="sub">Setup and settings for the desk viewer.</p>
<form id="f">
<div class="card"><h2>Status</h2>
<div class="st"><b>Wi-Fi</b><span id="sw"></span></div>
<div class="st"><b>Account</b><span id="sa"></span></div></div>
<div class="card"><div class="hd"><h2>Wi-Fi</h2><button type="button" id="scan" class="sm">Refresh</button></div>
<div id="cur" class="hint" style="margin:0 0 8px"></div>
<div id="nets"><div class="hint">Looking for networks...</div></div>
<input type="hidden" name="ssid">
<div id="other" style="display:none"><label>Network name</label><input id="ossid" autocomplete="off" placeholder="Hidden network name"></div>
<div id="pw" style="display:none"><label>Password for <span id="pwn"></span></label><input name="wpass" type="password" autocomplete="off" placeholder="Wi-Fi password"></div>
<p class="hint">Only 2.4 GHz networks show up. The ESP32 cannot use 5 GHz.</p></div>
<div class="card"><h2>Vox account</h2><p class="hint" style="margin:0 0 4px">Same email and password as the app.</p>
<label>Email</label><input name="email" type="email" autocomplete="off">
<label>Password</label><input name="vpass" type="password" placeholder="(unchanged)" autocomplete="off"></div>
<div class="card"><h2>Screen</h2>
<label>Brightness <span id="bv"></span></label><input name="bright" type="range" min="5" max="255">
<label>Screens a tap cycles through</label>
<div id="screens"></div>
<label>Idle screen (after no touch for a while). Home shows the face when nothing is due today.</label><select name="idle"></select>
<label>Go back to idle after (seconds)</label><input name="idleAfter" type="number" min="10" max="3600">
<div class="chk" style="margin-top:10px"><input type="checkbox" name="flip" id="flip"><span>Screen is mounted upside down</span></div>
<div class="chk"><input type="checkbox" name="clock24" id="clock24"><span>24 hour clock</span></div>
<label>Time zone</label><select name="tz" id="tz">
<option value="IST-5:30">India (IST)</option><option value="GMT0BST,M3.5.0/1,M10.5.0">United Kingdom</option><option value="CET-1CEST,M3.5.0,M10.5.0/3">Central Europe</option>
<option value="EST5EDT,M3.2.0,M11.1.0">US Eastern</option><option value="CST6CDT,M3.2.0,M11.1.0">US Central</option><option value="PST8PDT,M3.2.0,M11.1.0">US Pacific</option>
<option value="GST-4">Dubai (GST)</option><option value="SGT-8">Singapore</option><option value="JST-9">Japan</option><option value="AEST-10AEDT,M10.1.0,M4.1.0/3">Sydney</option><option value="UTC0">UTC</option><option value="custom">Custom...</option></select>
<input name="tzc" id="tzc" placeholder="POSIX string, e.g. IST-5:30" style="display:none;margin-top:8px"></div>
<button class="p" type="submit">Save</button>
<button type="button" id="rb" style="width:100%;margin-top:10px">Save and restart</button>
<p class="hint">Saving Wi-Fi or account details reconnects right away. The board keeps this page at its address on your Wi-Fi.</p>
</form></main><div id="msg"></div>
<script>
const $=s=>document.querySelector(s),f=$('#f'),N=%NAMES%;
function msg(t){const m=$('#msg');m.textContent=t;m.classList.add('on');setTimeout(()=>m.classList.remove('on'),2500)}
$('#screens').innerHTML=N.map((n,i)=>`<div class="chk"><input type="checkbox" name="s${i}" id="s${i}"><span>${n}</span></div>`).join('');
f.idle.innerHTML=N.map((n,i)=>`<option value="${i}">${n}</option>`).join('');
f.bright.oninput=()=>$('#bv').textContent=Math.round(f.bright.value/255*100)+'%';
$('#tz').onchange=()=>$('#tzc').style.display=$('#tz').value==='custom'?'block':'none';
let first=true,pick='';
async function load(){const s=await (await fetch('/state')).json();
$('#sw').innerHTML=s.wifi.startsWith('Connected')?`<span class="ok">${s.wifi}</span>`:`<span class="bad">${s.wifi}</span>`;
$('#sa').innerHTML=s.account==='Live'?'<span class="ok">Live</span>':`<span class="bad">${s.account}</span>`;
if(!first)return;first=false;
pick=s.ssid;f.ssid.value=s.ssid;$('#cur').textContent=s.ssid?'Saved: '+s.ssid:'No network saved yet. Pick one below.';
f.email.value=s.email;f.bright.value=s.bright;f.bright.oninput();f.idle.value=s.idle;f.idleAfter.value=s.idleAfter;f.flip.checked=s.flip;f.clock24.checked=s.clock24;
N.forEach((n,i)=>f['s'+i].checked=!!(s.screens&(1<<i)));
const o=[...$('#tz').options].find(o=>o.value===s.tz);$('#tz').value=o?s.tz:'custom';$('#tzc').value=s.tz;$('#tz').onchange()}
const esc=t=>t.replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function bars(r){const n=r>-55?4:r>-65?3:r>-75?2:1;return '<span class="bars">'+[6,9,12,14].map((h,i)=>`<i class="${i<n?'f':''}" style="height:${h}px"></i>`).join('')+'</span>'}
function choose(ssid,open){pick=ssid;f.ssid.value=ssid;
document.querySelectorAll('.net').forEach(b=>b.classList.toggle('on',b.dataset.s===ssid&&!b.dataset.other));
$('#other').style.display='none';$('#pw').style.display=open?'none':'block';$('#pwn').textContent=ssid;f.wpass.value='';if(!open)f.wpass.focus()}
async function scan(){$('#scan').textContent='Scanning...';$('#scan').disabled=true;
try{const r=await (await fetch('/scan')).json();
$('#nets').innerHTML=(r.length?r.map(n=>`<button type="button" class="net ${n.ssid===pick?'on':''}" data-s="${esc(n.ssid)}" data-open="${n.open?1:''}">${bars(n.rssi)}<span class="n">${esc(n.ssid)}</span>${n.open?'':'<span class="lock">&#128274;</span>'}</button>`).join(''):'<div class="hint">No networks found. Tap Refresh.</div>')
+'<button type="button" class="net" data-other="1"><span class="bars"></span><span class="n">Other network...</span></button>';
document.querySelectorAll('.net').forEach(b=>b.onclick=()=>{if(b.dataset.other){document.querySelectorAll('.net').forEach(x=>x.classList.toggle('on',x===b));$('#other').style.display='block';$('#pw').style.display='block';$('#pwn').textContent='this network';$('#ossid').focus();return}choose(b.dataset.s,!!b.dataset.open)})}
catch(e){$('#nets').innerHTML='<div class="hint">Scan failed. Tap Refresh.</div>'}
$('#scan').textContent='Refresh';$('#scan').disabled=false}
$('#ossid').oninput=()=>{pick=$('#ossid').value.trim();f.ssid.value=pick};
$('#scan').onclick=scan;
async function save(restart){const d=new URLSearchParams(new FormData(f));if($('#tz').value==='custom')d.set('tz',$('#tzc').value);d.set('screens',N.reduce((m,n,i)=>m|(f['s'+i].checked?1<<i:0),0));if(restart)d.set('restart','1');
const r=await fetch('/save',{method:'POST',body:d});msg(restart?'Saved. Restarting...':'Saved');if(!restart)setTimeout(load,2500)}
f.onsubmit=e=>{e.preventDefault();save(false)};$('#rb').onclick=()=>save(true);load().then(scan);setInterval(load,10000);
</script></body></html>)HTML";

static void sendPage() {
  String names = "[";
  for (int i = 0; i < SCR_COUNT; i++) names += String(i ? ",\"" : "\"") + SCREEN_NAMES[i] + "\"";
  names += "]";
  String page = FPSTR(PAGE);
  page.replace("%NAMES%", names);
  server.send(200, "text/html", page);
}

static void sendState() {
  JsonDocument d;
  d["ssid"] = S->wifiSSID;
  d["email"] = S->email;
  d["tz"] = S->timeZone;
  d["bright"] = S->brightness;
  d["screens"] = S->screens;
  d["idle"] = S->idle;
  d["idleAfter"] = S->idleAfter;
  d["flip"] = S->flip;
  d["clock24"] = S->clock24;
  d["wifi"] = lastStatus.wifi;
  d["account"] = lastStatus.account;
  String out;
  serializeJson(d, out);
  server.send(200, "application/json", out);
}

static void sendScan() {
  // A scan fails while the board is busy trying to join a network. Stop that attempt and try again.
  int n = WiFi.scanNetworks();
  for (int tries = 0; n < 0 && tries < 2; tries++) {
    WiFi.disconnect();
    delay(300);
    n = WiFi.scanNetworks();
  }
  JsonDocument d;
  JsonArray arr = d.to<JsonArray>();
  // Strongest first. The same name from several access points shows once, with the best signal.
  int order[32];
  int count = 0;
  for (int i = 0; i < n && count < 32; i++) order[count++] = i;
  for (int i = 1; i < count; i++)
    for (int j = i; j > 0 && WiFi.RSSI(order[j]) > WiFi.RSSI(order[j - 1]); j--) std::swap(order[j], order[j - 1]);
  for (int k = 0; k < count && arr.size() < 20; k++) {
    const int i = order[k];
    const String ssid = WiFi.SSID(i);
    if (!ssid.length()) continue;
    bool dup = false;
    for (JsonObject v : arr) if (ssid == (const char*)v["ssid"]) dup = true;
    if (dup) continue;
    JsonObject o = arr.add<JsonObject>();
    o["ssid"] = ssid;
    o["rssi"] = WiFi.RSSI(i);
    o["open"] = WiFi.encryptionType(i) == WIFI_AUTH_OPEN;
  }
  WiFi.scanDelete();
  String out;
  serializeJson(d, out);
  server.send(200, "application/json", out);
}

static void handleSave() {
  const String ssid = server.arg("ssid"), wpass = server.arg("wpass");
  const String email = server.arg("email"), vpass = server.arg("vpass");
  // A new network takes the password typed with it (empty for an open one). Same network, blank password: keep the old one.
  if (ssid.length() && (ssid != S->wifiSSID || wpass.length())) {
    savedWiFi = true;
    if (ssid != S->wifiSSID || wpass.length()) S->wifiPass = wpass;
    S->wifiSSID = ssid;
  }
  if (email != S->email || vpass.length()) { savedAccount = true; S->email = email; if (vpass.length()) S->password = vpass; }
  if (server.hasArg("tz") && server.arg("tz").length()) S->timeZone = server.arg("tz");
  S->brightness = constrain(server.arg("bright").toInt(), 5, 255);
  S->screens = server.arg("screens").toInt() & ALL_SCREENS;
  if (S->screens == 0) S->screens = 1 << SCR_CLOCK;
  S->idle = constrain(server.arg("idle").toInt(), 0, SCR_COUNT - 1);
  if (!S->shows((Screen)S->idle)) for (int i = 0; i < SCR_COUNT; i++) if (S->shows((Screen)i)) { S->idle = i; break; }
  S->idleAfter = constrain(server.arg("idleAfter").toInt(), 10, 3600);
  S->flip = server.hasArg("flip");
  S->clock24 = server.hasArg("clock24");
  settingsSave(*S);
  saved = true;
  if (server.hasArg("restart")) restartWanted = true;
  server.send(200, "text/plain", "ok");
}

// Phones check these addresses to see if a Wi-Fi has internet. Answering with a redirect makes the setup page pop up.
static void handleNotFound() {
  server.sendHeader("Location", "http://" + WiFi.softAPIP().toString() + "/", true);
  server.send(302, "text/plain", "");
}

void portalBegin(Settings* settings) {
  S = settings;
  server.on("/", HTTP_GET, sendPage);
  server.on("/state", HTTP_GET, sendState);
  server.on("/scan", HTTP_GET, sendScan);
  server.on("/save", HTTP_POST, handleSave);
  server.onNotFound(handleNotFound);
  server.begin();
}

void portalOpenAP() {
  if (apOpen) return;
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(AP_NAME);
  dns.setErrorReplyCode(DNSReplyCode::NoError);
  dns.start(53, "*", WiFi.softAPIP());
  apOpen = true;
  Serial.printf("Setup Wi-Fi '%s' at %s\n", AP_NAME, WiFi.softAPIP().toString().c_str());
}

void portalCloseAP() {
  if (!apOpen) return;
  dns.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_STA);
  apOpen = false;
}

bool portalAPOpen() { return apOpen; }
String portalAPName() { return AP_NAME; }

void portalLoop(const PortalStatus& status) {
  lastStatus = status;
  if (apOpen) dns.processNextRequest();
  server.handleClient();
}

bool portalTakeSaved(bool* wifiChanged, bool* accountChanged) {
  if (!saved) return false;
  *wifiChanged = savedWiFi;
  *accountChanged = savedAccount;
  saved = savedWiFi = savedAccount = false;
  return true;
}

bool portalTakeRestart() {
  const bool r = restartWanted;
  restartWanted = false;
  return r;
}
