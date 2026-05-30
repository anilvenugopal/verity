import { useState, useCallback } from "react";

const T = {
  bg:"#F7F6F3",surface:"#FFFFFF",surfaceHi:"#F0EEE9",border:"#E2DDD6",
  borderHi:"#C8C2B8",muted:"#9A9488",dim:"#6B6560",body:"#3D3A36",
  bright:"#1A1816",amber:"#A06820",amberDim:"#FDF3E3",amberBorder:"#E8C07A",
  teal:"#1A7A68",tealDim:"#E6F4F1",tealBorder:"#7ECAB8",
  purple:"#5B4DB8",purpleDim:"#EEEAF8",purpleBorder:"#B0A4E8",
  coral:"#B84040",coralDim:"#FAEAEA",coralBorder:"#E8A0A0",
  green:"#2A7A48",greenDim:"#E6F4EC",greenBorder:"#80C8A0",
  blue:"#1A5FA0",blueDim:"#E6F0FA",blueBorder:"#80B8E8",
};

const VS = {
  string: {accent:T.teal,  bg:T.tealDim,  border:T.tealBorder,  tag:"str" },
  number: {accent:T.amber, bg:T.amberDim, border:T.amberBorder, tag:"num" },
  code:   {accent:T.green, bg:T.greenDim, border:T.greenBorder, tag:"code"},
  enum:   {accent:T.purple,bg:T.purpleDim,border:T.purpleBorder,tag:"enum"},
  boolean:{accent:T.coral, bg:T.coralDim, border:T.coralBorder, tag:"bool"},
};

const AC = {"Arjun V":T.teal,"Ritu K":T.purple,"Mei S":T.amber};

const INITIAL = [
  {id:"s1",kind:"prose",text:"You are a senior engineer. Be precise, avoid boilerplate, and match existing patterns in the codebase.",blame:{author:"Arjun V",sha:"a3f9c2",age:"3d ago",msg:"initial system prompt"}},
  {id:"s2",kind:"var",name:"language",type:"enum",desc:"Target programming language. Controls idioms, types, and standard library references in the output.",eg:"TypeScript",opts:["TypeScript","Python","Go","Rust","Swift"],req:true,blame:{author:"Ritu K",sha:"d1e8b7",age:"2d ago",msg:"add language slot"}},
  {id:"s3",kind:"prose",text:"The developer needs to implement the following:",blame:{author:"Arjun V",sha:"a3f9c2",age:"3d ago",msg:"initial system prompt"}},
  {id:"s4",kind:"var",name:"task",type:"string",desc:"Clear description of what to build. Include file paths, function names, or API contracts if known.",eg:"Add rate-limiting middleware — 100 req/min per IP — using the Redis client in src/lib/redis.ts",req:true,blame:{author:"Arjun V",sha:"a3f9c2",age:"3d ago",msg:"initial system prompt"}},
  {id:"s5",kind:"var",name:"constraints",type:"string",desc:"Existing patterns to follow, libraries in use, or things to avoid.",eg:"Follow the repository pattern in src/repos/. No new npm packages.",req:false,blame:{author:"Mei S",sha:"f9c341",age:"6h ago",msg:"make constraints optional"}},
  {id:"s6",kind:"prose",text:"Respond with:",blame:{author:"Ritu K",sha:"d1e8b7",age:"2d ago",msg:"add response format"}},
  {id:"s7",kind:"list",items:["A two-sentence explanation of your approach","Complete, runnable implementation","Edge cases or caveats the developer should know"],blame:{author:"Ritu K",sha:"d1e8b7",age:"2d ago",msg:"add response format"}},
  {id:"s8",kind:"table",caption:"Response format by verbosity level",headers:["Verbosity","Code style","Comments","Prose explanation"],rows:[["concise","complete","inline only","2 sentences"],["balanced","complete","per section","1 paragraph"],["teaching","complete","extensive","full walkthrough"]],blame:{author:"Mei S",sha:"f9c341",age:"6h ago",msg:"add verbosity reference table"}},
  {id:"s10",kind:"code",lang:"typescript",caption:"Existing pattern to follow",code:`// Example: how repositories are structured in this codebase
export class UserRepository {
  constructor(private readonly db: Database) {}

  async findById(id: string): Promise<User | null> {
    return this.db.queryOne<User>(
      'SELECT * FROM users WHERE id = $1',
      [id]
    );
  }
}`,blame:{author:"Ritu K",sha:"d1e8b7",age:"2d ago",msg:"add codebase pattern example"}},
  {id:"s9",kind:"var",name:"verbosity",type:"enum",desc:"Controls how much explanation accompanies the code.",eg:"concise",opts:["concise","balanced","teaching"],req:false,blame:{author:"Mei S",sha:"f9c341",age:"6h ago",msg:"add verbosity control"}},
];

function Pill({color,bg,border,children}) {
  return <span style={{display:"inline-flex",alignItems:"center",padding:"0 5px",borderRadius:3,background:bg,border:`1px solid ${border||color+"44"}`,fontSize:10,fontFamily:"monospace",color,lineHeight:"18px",fontWeight:600}}>{children}</span>;
}

function Avatar({author,size=18}) {
  const color=AC[author]??T.dim;
  return <span style={{display:"inline-flex",alignItems:"center",justifyContent:"center",width:size,height:size,borderRadius:"50%",background:color+"18",border:`1px solid ${color}55`,fontSize:Math.floor(size*.45),color,fontWeight:700,flexShrink:0}}>{author[0]}</span>;
}

function VarChip({seg,isEditing,onEdit,onClose}) {
  const s=VS[seg.type]??VS.string;
  const [val,setVal]=useState(seg.eg??"");
  return (
    <span style={{display:"inline-block",position:"relative",verticalAlign:"middle"}}>
      <button onClick={isEditing?onClose:onEdit} style={{display:"inline-flex",alignItems:"center",gap:5,background:s.bg,border:`1px solid ${s.border}`,borderRadius:5,padding:"3px 9px",cursor:"pointer",boxShadow:isEditing?`0 0 0 2px ${s.accent}33`:"none",transition:"box-shadow .12s"}}>
        <Pill color={s.accent} bg={s.bg} border={s.border}>{s.tag}</Pill>
        <span style={{fontSize:13,color:s.accent,fontFamily:"'JetBrains Mono','Fira Code',monospace",fontWeight:600}}>{seg.name}</span>
        {!seg.req&&<span style={{fontSize:10,color:T.muted}}>?</span>}
      </button>
      {isEditing&&(
        <div style={{position:"absolute",top:"calc(100% + 8px)",left:0,width:300,zIndex:200,background:T.surface,border:`1px solid ${s.border}`,borderTop:`2px solid ${s.accent}`,borderRadius:8,padding:14,boxShadow:"0 8px 32px rgba(0,0,0,.12)"}}>
          <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:8}}>
            <Pill color={s.accent} bg={s.bg} border={s.border}>{seg.type}{!seg.req?" · optional":""}</Pill>
            <button onClick={onClose} style={{background:"none",border:"none",color:T.muted,cursor:"pointer",fontSize:18,lineHeight:1,padding:0}}>×</button>
          </div>
          <p style={{margin:"0 0 10px",fontSize:12,color:T.dim,lineHeight:1.6}}>{seg.desc}</p>
          {seg.type==="enum"?(
            <div style={{display:"flex",gap:5,flexWrap:"wrap"}}>
              {(seg.opts||[]).map(o=>(
                <button key={o} onClick={()=>setVal(o)} style={{padding:"3px 9px",borderRadius:4,fontSize:12,background:val===o?s.bg:"transparent",border:`1px solid ${val===o?s.accent:T.border}`,color:val===o?s.accent:T.dim,cursor:"pointer",fontFamily:"monospace",transition:"all .1s"}}>{o}</button>
              ))}
            </div>
          ):(
            <div>
              <div style={{fontSize:10,color:T.muted,marginBottom:4,fontFamily:"monospace"}}>value</div>
              <input value={val} onChange={e=>setVal(e.target.value)} placeholder={seg.eg} style={{width:"100%",boxSizing:"border-box",background:T.surfaceHi,border:`1px solid ${s.border}`,borderRadius:4,padding:"5px 8px",fontSize:12,color:T.bright,fontFamily:"monospace",outline:"none"}}/>
            </div>
          )}
          <div style={{marginTop:10,fontSize:11,color:T.muted,fontStyle:"italic",paddingTop:8,borderTop:`1px solid ${T.border}`}}>Example: {seg.eg}</div>
        </div>
      )}
    </span>
  );
}

function TableBlock({seg}) {
  return (
    <div style={{overflowX:"auto"}}>
      {seg.caption&&<p style={{margin:"0 0 6px",fontSize:11,color:T.muted,fontStyle:"italic"}}>{seg.caption}</p>}
      <table style={{borderCollapse:"collapse",fontSize:12,width:"100%",minWidth:360}}>
        <thead>
          <tr>
            {seg.headers.map((h,i)=>(
              <th key={i} style={{padding:"6px 12px",textAlign:"left",background:T.surfaceHi,border:`1px solid ${T.border}`,color:T.body,fontWeight:600,fontSize:11,letterSpacing:.3}}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {seg.rows.map((row,ri)=>(
            <tr key={ri} style={{background:ri%2===0?T.surface:T.bg}}>
              {row.map((cell,ci)=>(
                <td key={ci} style={{padding:"5px 12px",border:`1px solid ${T.border}`,color:T.body,fontFamily:ci===0?"monospace":"inherit",fontSize:ci===0?11:12}}>{cell}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const LANG_COLORS = {
  typescript:{color:"#3178C6",label:"TS"},javascript:{color:"#F7DF1E",label:"JS"},
  python:{color:"#3776AB",label:"PY"},sql:{color:"#E38C00",label:"SQL"},
  bash:{color:"#4EAA25",label:"SH"},json:{color:"#888",label:"{}"},
  go:{color:"#00ACD7",label:"GO"},rust:{color:"#CE412B",label:"RS"},
  yaml:{color:"#CB171E",label:"YML"},text:{color:"#888",label:"TXT"},
};

function CodeBlock({seg}) {
  const [copied,setCopied]=useState(false);
  const lang=LANG_COLORS[seg.lang]??{color:"#888",label:"CODE"};
  const copy=()=>{navigator.clipboard?.writeText(seg.code||"");setCopied(true);setTimeout(()=>setCopied(false),1500);};
  return (
    <div style={{border:`1px solid ${T.border}`,borderRadius:6,overflow:"hidden",background:T.surfaceHi}}>
      {/* Header bar */}
      <div style={{display:"flex",alignItems:"center",gap:8,padding:"5px 10px",background:T.surface,borderBottom:`1px solid ${T.border}`}}>
        <span style={{fontSize:10,fontFamily:"monospace",fontWeight:700,color:lang.color,background:lang.color+"15",padding:"1px 5px",borderRadius:3,border:`1px solid ${lang.color}33`}}>{lang.label}</span>
        {seg.lang&&<span style={{fontSize:11,color:T.muted,fontFamily:"monospace"}}>{seg.lang}</span>}
        {seg.caption&&<span style={{fontSize:11,color:T.dim,fontStyle:"italic",marginLeft:4}}>— {seg.caption}</span>}
        <div style={{flex:1}}/>
        <button onClick={copy} style={{background:"none",border:`1px solid ${T.border}`,borderRadius:4,padding:"2px 8px",fontSize:11,color:copied?T.green:T.muted,cursor:"pointer",transition:"color .2s",fontFamily:"monospace"}}>
          {copied?"copied ✓":"copy"}
        </button>
      </div>
      {/* Code body */}
      <div style={{overflowX:"auto"}}>
        <pre style={{margin:0,padding:"12px 14px",fontSize:12,fontFamily:"'JetBrains Mono','Fira Code','Cascadia Code',monospace",lineHeight:1.7,color:T.body,whiteSpace:"pre",background:"transparent"}}>
          {(seg.code||"").split("\n").map((line,i)=>(
            <div key={i} style={{display:"flex",gap:0,minHeight:"1.7em"}}>
              <span style={{userSelect:"none",color:T.border,fontSize:10,lineHeight:"1.7em",minWidth:28,textAlign:"right",paddingRight:12,flexShrink:0,fontVariantNumeric:"tabular-nums"}}>{i+1}</span>
              <span style={{flex:1}}>{line||" "}</span>
            </div>
          ))}
        </pre>
      </div>
    </div>
  );
}

function SegRow({seg,onBlameClick,editingVar,onEditVar,onCloseVar}) {
  const [hov,setHov]=useState(false);
  const color=AC[seg.blame.author]??T.dim;
  return (
    <div onMouseEnter={()=>setHov(true)} onMouseLeave={()=>setHov(false)} style={{display:"flex",alignItems:"flex-start",padding:"1px 16px 1px 0"}}>
      <div onClick={()=>onBlameClick(seg.blame)} title={`${seg.blame.author} · ${seg.blame.msg}`} style={{width:36,flexShrink:0,display:"flex",flexDirection:"column",alignItems:"center",paddingTop:10,gap:3,cursor:"pointer",opacity:hov?1:0.25,transition:"opacity .15s"}}>
        <div style={{width:2,height:24,borderRadius:1,background:color}}/>
        <span style={{fontSize:9,color,fontFamily:"monospace"}}>{seg.blame.author.split(" ").map(p=>p[0]).join("")}</span>
      </div>
      <div style={{flex:1,padding:"7px 10px",borderRadius:6,background:hov?T.surfaceHi:"transparent",transition:"background .12s"}}>
        {seg.kind==="prose"&&<p style={{margin:0,fontSize:14,color:T.body,lineHeight:1.75,fontFamily:"Georgia,'Times New Roman',serif"}}>{seg.text}</p>}
        {seg.kind==="var"&&<VarChip seg={seg} isEditing={editingVar===seg.id} onEdit={()=>onEditVar(seg.id)} onClose={onCloseVar}/>}
        {seg.kind==="list"&&(
          <ul style={{margin:0,padding:"0 0 0 18px"}}>
            {seg.items.map((it,i)=><li key={i} style={{fontSize:13,color:T.dim,lineHeight:1.8,fontFamily:"Georgia,serif"}}>{it}</li>)}
          </ul>
        )}
        {seg.kind==="table"&&<TableBlock seg={seg}/>}
        {seg.kind==="code"&&<CodeBlock seg={seg}/>}
      </div>
    </div>
  );
}

function InsertZone({onInsert}) {
  const [hov,setHov]=useState(false);
  return (
    <div onMouseEnter={()=>setHov(true)} onMouseLeave={()=>setHov(false)} onClick={onInsert} style={{height:10,margin:"0 0 0 36px",display:"flex",alignItems:"center",cursor:"pointer"}}>
      <div style={{height:1,flex:1,background:hov?T.amber+"66":"transparent",transition:"background .15s",borderRadius:1,position:"relative"}}>
        {hov&&<span style={{position:"absolute",right:0,top:"50%",transform:"translateY(-50%)",fontSize:9,color:T.amber,background:T.amberDim,border:`1px solid ${T.amberBorder}`,padding:"1px 6px",borderRadius:3,fontFamily:"monospace"}}>⊕ insert</span>}
      </div>
    </div>
  );
}

function AddPanel({onAdd,onClose}) {
  const [mode,setMode]=useState(null);
  const [prose,setProse]=useState("");
  const [form,setForm]=useState({name:"",type:"string",desc:"",eg:"",req:true});
  const [tform,setTform]=useState({caption:"",headers:"Col A, Col B, Col C",rows:"val1, val2, val3\nval4, val5, val6"});
  const [cform,setCform]=useState({lang:"typescript",caption:"",code:"// paste or type code here\n"});

  const btnStyle=(color,bg,border)=>({background:bg,border:`1px solid ${border}`,color,borderRadius:5,padding:"4px 11px",fontSize:12,cursor:"pointer"});

  if(!mode) return (
    <div style={{margin:"4px 0 4px 36px",padding:"10px 12px",background:T.surface,border:`1px solid ${T.border}`,borderRadius:6,display:"flex",gap:8,flexWrap:"wrap"}}>
      <button onClick={()=>setMode("var")} style={btnStyle(T.teal,T.tealDim,T.tealBorder)}>+ {"{variable}"}</button>
      <button onClick={()=>setMode("prose")} style={btnStyle(T.amber,T.amberDim,T.amberBorder)}>+ prose</button>
      <button onClick={()=>setMode("list")} style={btnStyle(T.purple,T.purpleDim,T.purpleBorder)}>+ list</button>
      <button onClick={()=>setMode("table")} style={btnStyle(T.blue,T.blueDim,T.blueBorder)}>+ table</button>
      <button onClick={()=>setMode("code")} style={btnStyle(T.green,T.greenDim,T.greenBorder)}>+ code</button>
      <button onClick={onClose} style={{background:"transparent",border:`1px solid ${T.border}`,color:T.muted,borderRadius:5,padding:"4px 10px",fontSize:12,cursor:"pointer",marginLeft:"auto"}}>cancel</button>
    </div>
  );

  const inputStyle={width:"100%",boxSizing:"border-box",background:T.surfaceHi,border:`1px solid ${T.border}`,borderRadius:4,padding:"5px 8px",fontSize:12,color:T.bright,outline:"none"};
  const actionRow=<div style={{display:"flex",gap:8,marginTop:8}}>
    <button onClick={()=>{
      if(mode==="prose"&&prose.trim()) onAdd({kind:"prose",text:prose});
      if(mode==="list"&&prose.trim()) onAdd({kind:"list",items:prose.split("\n").map(s=>s.trim()).filter(Boolean)});
      if(mode==="code") onAdd({kind:"code",lang:cform.lang,caption:cform.caption,code:cform.code});
      if(mode==="table") {
        const headers=tform.headers.split(",").map(s=>s.trim());
        const rows=tform.rows.split("\n").map(r=>r.split(",").map(s=>s.trim()));
        onAdd({kind:"table",caption:tform.caption,headers,rows});
      }
      if(mode==="var"&&form.name) onAdd({kind:"var",...form,opts:form.type==="enum"?[]:undefined});
    }} style={btnStyle(mode==="var"?T.teal:T.amber,mode==="var"?T.tealDim:T.amberDim,mode==="var"?T.tealBorder:T.amberBorder)}>insert</button>
    <button onClick={onClose} style={{background:"transparent",border:`1px solid ${T.border}`,color:T.muted,borderRadius:5,padding:"4px 10px",fontSize:12,cursor:"pointer"}}>cancel</button>
  </div>;

  if(mode==="prose"||mode==="list") return (
    <div style={{margin:"4px 0 4px 36px",padding:"10px 12px",background:T.surface,border:`1px solid ${T.border}`,borderRadius:6}}>
      <div style={{fontSize:10,color:T.muted,marginBottom:4}}>{mode==="list"?"one item per line":"prose text"}</div>
      <textarea autoFocus value={prose} onChange={e=>setProse(e.target.value)} rows={3} style={{...inputStyle,fontFamily:mode==="list"?"monospace":"Georgia,serif",resize:"vertical"}}/>
      {actionRow}
    </div>
  );

  if(mode==="table") return (
    <div style={{margin:"4px 0 4px 36px",padding:"10px 12px",background:T.surface,border:`1px solid ${T.border}`,borderRadius:6}}>
      <div style={{display:"flex",flexDirection:"column",gap:6}}>
        <input placeholder="Table caption (optional)" value={tform.caption} onChange={e=>setTform(f=>({...f,caption:e.target.value}))} style={inputStyle}/>
        <div style={{fontSize:10,color:T.muted}}>Headers (comma-separated)</div>
        <input value={tform.headers} onChange={e=>setTform(f=>({...f,headers:e.target.value}))} style={{...inputStyle,fontFamily:"monospace"}}/>
        <div style={{fontSize:10,color:T.muted}}>Rows (one per line, values comma-separated)</div>
        <textarea value={tform.rows} onChange={e=>setTform(f=>({...f,rows:e.target.value}))} rows={3} style={{...inputStyle,fontFamily:"monospace",resize:"vertical"}}/>
      </div>
      {actionRow}
    </div>
  );

  if(mode==="code") return (
    <div style={{margin:"4px 0 4px 36px",padding:"10px 12px",background:T.surface,border:`1px solid ${T.border}`,borderRadius:6}}>
      <div style={{display:"flex",gap:8,marginBottom:8}}>
        <select value={cform.lang} onChange={e=>setCform(f=>({...f,lang:e.target.value}))} style={{background:T.surfaceHi,border:`1px solid ${T.border}`,borderRadius:4,padding:"5px 8px",fontSize:12,color:T.body,outline:"none"}}>
          {Object.keys(LANG_COLORS).map(l=><option key={l} value={l}>{l}</option>)}
        </select>
        <input value={cform.caption} onChange={e=>setCform(f=>({...f,caption:e.target.value}))} placeholder="Caption (optional)" style={{flex:1,background:T.surfaceHi,border:`1px solid ${T.border}`,borderRadius:4,padding:"5px 8px",fontSize:12,color:T.body,outline:"none"}}/>
      </div>
      <textarea value={cform.code} onChange={e=>setCform(f=>({...f,code:e.target.value}))} rows={6} spellCheck={false} style={{width:"100%",boxSizing:"border-box",background:T.surfaceHi,border:`1px solid ${T.greenBorder}`,borderRadius:4,padding:"8px 10px",fontSize:12,color:T.bright,fontFamily:"'JetBrains Mono','Fira Code',monospace",outline:"none",resize:"vertical",lineHeight:1.6}}/>
      {actionRow}
    </div>
  );

  return (
    <div style={{margin:"4px 0 4px 36px",padding:"10px 12px",background:T.surface,border:`1px solid ${T.border}`,borderRadius:6}}>
      <div style={{display:"flex",gap:8,marginBottom:8}}>
        <input autoFocus value={form.name} onChange={e=>setForm(f=>({...f,name:e.target.value.replace(/[^a-z0-9_]/gi,"_").toLowerCase()}))} placeholder="variable_name" style={{...inputStyle,flex:1,fontFamily:"monospace"}}/>
        <select value={form.type} onChange={e=>setForm(f=>({...f,type:e.target.value}))} style={{background:T.surfaceHi,border:`1px solid ${T.border}`,borderRadius:4,padding:"5px 8px",fontSize:12,color:T.body,outline:"none"}}>
          {Object.keys(VS).map(t=><option key={t}>{t}</option>)}
        </select>
      </div>
      <input value={form.desc} onChange={e=>setForm(f=>({...f,desc:e.target.value}))} placeholder="Guidance shown when filling this variable…" style={{...inputStyle,marginBottom:8}}/>
      <input value={form.eg} onChange={e=>setForm(f=>({...f,eg:e.target.value}))} placeholder="Example value" style={{...inputStyle,fontFamily:"monospace",marginBottom:8}}/>
      {form.type==="enum"&&<input value={form.opts?.join(", ")||""} onChange={e=>setForm(f=>({...f,opts:e.target.value.split(",").map(s=>s.trim())}))} placeholder="Options: opt1, opt2, opt3" style={{...inputStyle,fontFamily:"monospace",marginBottom:8}}/>}
      <label style={{fontSize:12,color:T.dim,display:"flex",alignItems:"center",gap:5,marginBottom:8}}>
        <input type="checkbox" checked={form.req} onChange={e=>setForm(f=>({...f,req:e.target.checked}))}/>required
      </label>
      {actionRow}
    </div>
  );
}

// Compile: preserve newlines between blocks, render tables as markdown
function compileDoc(doc) {
  return doc.map(s=>{
    if(s.kind==="prose") return s.text;
    if(s.kind==="var") return `{${s.name}}`;
    if(s.kind==="list") return s.items.map((it,i)=>`${i+1}. ${it}`).join("\n");
    if(s.kind==="code") return `\`\`\`${s.lang||""}\n${s.code||""}\n\`\`\``;
    if(s.kind==="table") {
      const sep=s.headers.map(()=>"---").join(" | ");
      const head=s.headers.join(" | ");
      const rows=s.rows.map(r=>r.join(" | ")).join("\n");
      return `${s.caption?s.caption+"\n":""}\n${head}\n${sep}\n${rows}`;
    }
    return "";
  }).filter(Boolean).join("\n\n");
}

export default function App() {
  const [doc,setDoc]=useState(INITIAL);
  const [activeBlame,setActiveBlame]=useState(null);
  const [editingVar,setEditingVar]=useState(null);
  const [insertAfter,setInsertAfter]=useState(null);
  const [compiled,setCompiled]=useState(false);

  const vars=doc.filter(s=>s.kind==="var");
  const blameLog=[...new Map(doc.map(s=>[s.blame.sha,s.blame])).values()];

  const handleAdd=useCallback((afterIdx,node)=>{
    setDoc(d=>{
      const next=[...d];
      const label=node.kind==="var"?`added {${node.name}}`:node.kind==="table"?"added table":node.kind==="code"?`added ${node.lang||"code"} block`:`added ${node.kind}`;
      next.splice(afterIdx+1,0,{id:`s${Date.now()}`,blame:{author:"You",sha:"local",age:"just now",msg:label},...node});
      return next;
    });
    setInsertAfter(null);
  },[]);

  return (
    <div style={{display:"flex",height:"100vh",background:T.bg,color:T.body,fontFamily:"system-ui,sans-serif",overflow:"hidden"}}>

      {/* Editor */}
      <div style={{flex:1,display:"flex",flexDirection:"column",minWidth:0}}>
        {/* Toolbar */}
        <div style={{display:"flex",alignItems:"center",gap:12,padding:"10px 16px",borderBottom:`1px solid ${T.border}`,background:T.surface,flexShrink:0}}>
          <span style={{fontSize:12,color:T.amber,fontFamily:"monospace",fontWeight:700,letterSpacing:.5}}>⬡ PROMPT</span>
          <span style={{fontSize:11,color:T.muted}}>code guide template</span>
          <div style={{flex:1}}/>
          <div style={{display:"flex",gap:4}}>
            {Object.keys(AC).map(n=><Avatar key={n} author={n} size={20}/>)}
          </div>
          <button onClick={()=>setCompiled(c=>!c)} style={{background:compiled?T.purpleDim:"transparent",border:`1px solid ${compiled?T.purpleBorder:T.border}`,color:compiled?T.purple:T.dim,borderRadius:5,padding:"4px 12px",fontSize:11,cursor:"pointer",transition:"all .15s"}}>
            {compiled?"← edit":"compile →"}
          </button>
        </div>

        {/* Body */}
        <div style={{flex:1,overflowY:"auto",padding:"16px 0"}}>
          {compiled?(
            <div style={{padding:"16px 24px"}}>
              <div style={{fontSize:10,color:T.muted,fontFamily:"monospace",marginBottom:8,textTransform:"uppercase",letterSpacing:2}}>compiled · newlines preserved · tables as markdown</div>
              <pre style={{background:T.surface,border:`1px solid ${T.border}`,borderRadius:8,padding:16,fontFamily:"'JetBrains Mono','Fira Code',monospace",fontSize:12,color:T.body,whiteSpace:"pre-wrap",lineHeight:1.75,margin:0}}>{compileDoc(doc)}</pre>
            </div>
          ):(
            <>
              {doc.map((seg,idx)=>(
                <div key={seg.id}>
                  <SegRow seg={seg} onBlameClick={bl=>setActiveBlame(b=>b?.sha===bl.sha?null:bl)} editingVar={editingVar} onEditVar={id=>{setEditingVar(id);setInsertAfter(null);}} onCloseVar={()=>setEditingVar(null)}/>
                  {insertAfter===idx?(
                    <AddPanel onAdd={node=>handleAdd(idx,node)} onClose={()=>setInsertAfter(null)}/>
                  ):(
                    <InsertZone onInsert={()=>{setInsertAfter(idx);setEditingVar(null);}}/>
                  )}
                </div>
              ))}
            </>
          )}
        </div>

        {/* Status */}
        <div style={{display:"flex",alignItems:"center",gap:12,padding:"5px 16px",borderTop:`1px solid ${T.border}`,background:T.surface,fontSize:11,color:T.muted,flexShrink:0}}>
          <span style={{fontFamily:"monospace"}}>{vars.length} vars · {vars.filter(v=>v.req).length} required · {doc.length} blocks</span>
          <div style={{flex:1}}/>
          <span>hover gutter for blame · click variable to configure</span>
        </div>
      </div>

      {/* Right panel */}
      <div style={{width:210,borderLeft:`1px solid ${T.border}`,background:T.surface,display:"flex",flexDirection:"column",flexShrink:0,overflowY:"auto"}}>
        <div style={{padding:"10px 12px 8px",borderBottom:`1px solid ${T.border}`}}>
          <span style={{fontSize:9,color:T.muted,textTransform:"uppercase",letterSpacing:2}}>variables</span>
        </div>
        {vars.map(seg=>{
          const s=VS[seg.type]??VS.string;
          return (
            <div key={seg.id} onClick={()=>setEditingVar(id=>id===seg.id?null:seg.id)} style={{padding:"8px 12px",borderBottom:`1px solid ${T.bg}`,cursor:"pointer",background:editingVar===seg.id?T.surfaceHi:"transparent",transition:"background .1s"}}>
              <div style={{display:"flex",alignItems:"center",gap:5,marginBottom:2}}>
                <Pill color={s.accent} bg={s.bg} border={s.border}>{s.tag}</Pill>
                <span style={{fontSize:12,color:s.accent,fontFamily:"monospace",fontWeight:600}}>{seg.name}</span>
                {!seg.req&&<span style={{fontSize:9,color:T.muted}}>opt</span>}
              </div>
              <p style={{margin:0,fontSize:11,color:T.dim,lineHeight:1.4}}>{(seg.desc||"").slice(0,70)}{(seg.desc||"").length>70?"…":""}</p>
            </div>
          );
        })}

        <div style={{padding:"10px 12px 8px",borderBottom:`1px solid ${T.border}`,marginTop:8}}>
          <span style={{fontSize:9,color:T.muted,textTransform:"uppercase",letterSpacing:2}}>blame log</span>
        </div>
        {blameLog.map(bl=>{
          const color=AC[bl.author]??T.amber;
          return (
            <div key={bl.sha} onClick={()=>setActiveBlame(b=>b?.sha===bl.sha?null:bl)} style={{padding:"7px 12px",borderBottom:`1px solid ${T.bg}`,cursor:"pointer",background:activeBlame?.sha===bl.sha?T.surfaceHi:"transparent",transition:"background .1s"}}>
              <div style={{display:"flex",alignItems:"center",gap:6,marginBottom:2}}>
                <Avatar author={bl.author} size={14}/>
                <span style={{fontSize:11,color,fontFamily:"monospace"}}>{bl.sha}</span>
                <span style={{fontSize:10,color:T.muted,marginLeft:"auto"}}>{bl.age}</span>
              </div>
              <p style={{margin:0,fontSize:11,color:T.dim,fontStyle:"italic"}}>{bl.msg}</p>
            </div>
          );
        })}
      </div>

      {/* Blame tooltip */}
      {activeBlame&&(
        <div style={{position:"fixed",bottom:40,left:"50%",transform:"translateX(-50%)",background:T.surface,border:`1px solid ${T.border}`,borderLeft:`3px solid ${AC[activeBlame.author]??T.amber}`,borderRadius:8,padding:"10px 16px",display:"flex",alignItems:"center",gap:12,zIndex:500,boxShadow:"0 8px 32px rgba(0,0,0,.12)",minWidth:320}}>
          <Avatar author={activeBlame.author} size={28}/>
          <div style={{flex:1}}>
            <div style={{fontSize:12,color:T.bright,fontWeight:600}}>{activeBlame.author}</div>
            <div style={{fontSize:11,color:T.muted,fontFamily:"monospace",marginTop:1}}>{activeBlame.sha} · {activeBlame.age}</div>
            <div style={{fontSize:12,color:T.body,marginTop:2,fontStyle:"italic"}}>"{activeBlame.msg}"</div>
          </div>
          <button onClick={()=>setActiveBlame(null)} style={{background:"none",border:"none",color:T.muted,cursor:"pointer",fontSize:20,lineHeight:1,padding:0}}>×</button>
        </div>
      )}
    </div>
  );
}
