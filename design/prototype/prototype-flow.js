/* Layerly prototype: local navigation, model demonstration and explicit print review. */
(() => {
 const P=Prototype,{ $, $$, text, esc, link, match, nav, go, modal, status, read, save, download }=P;
 const file=location.pathname.split('/').pop();
 nav('.nav-item',{总览:'dashboard.html',作品:'projects.html',设备:'devices.html',材料:'materials.html',历史:'history.html',顾问:'advisor.html'});
 const pref=()=>modal('原型偏好','仅影响当前浏览器；设备和模型服务均未连接。',[{label:'外观',name:'theme',options:['亮色','暗色'],value:document.body.classList.contains('dark')?'暗色':'亮色'}],d=>{document.body.classList.toggle('dark',d.theme==='暗色');save('dark',d.theme==='暗色')},'应用');
 $$('button[title="设置"]').forEach(b=>link(b,pref));
 $('.toggle')?.addEventListener('click',()=>save('dark',document.body.classList.contains('dark')));
 const routeButtons={'全部作品':'projects.html','← 作品':'projects.html','← 相机快装板':'project.html','历史 →':'history.html','设备详情':'devices.html','打开顾问':'advisor.html','模型查看器':'model-viewer.html','准备打印':'print-prep.html','比较全部':'print-prep.html','跳过，先逛逛':'dashboard.html'};
 Object.entries(routeButtons).forEach(([label,dest])=>match('button',new RegExp(label),()=>go(dest)));
 $$('.project-card').forEach(card=>link(card,e=>{if(!e.matches('button'))go('project.html')}));
 const projects=read('projects',[]);
 function createProject(){modal('新作品','创建一个本地示例项目。',[{label:'作品名',name:'name',required:true},{label:'需求',name:'brief',type:'textarea'}],d=>{const name=d.name.trim();if(!name)return false;projects.unshift({name,brief:d.brief});save('projects',projects);save('selected',projects[0]);go('project.html?sample=local')},'创建')}
 match('button',/^新作品$/,createProject);
 if(file==='projects.html'&&projects.length){const grid=$('.project-card')?.parentElement;projects.forEach(project=>{const card=document.createElement('div');card.className='card project-card';card.innerHTML=`<div class="pc-body" style="padding:18px"><span class="pill idea">Idea</span><h2>${esc(project.name)}</h2><p>${esc(project.brief)}</p></div>`;link(card,()=>{save('selected',project);go('project.html?sample=local')});grid?.prepend(card)})}
 if(file==='project.html'&&new URLSearchParams(location.search).has('sample')){
   const project=read('selected',{});$('h1').textContent=project.name||'新作品';
   const pill=$('.topbar .pill');if(pill){pill.className='pill idea';pill.textContent='Idea'}
   const content=$('.content');if(content){content.replaceChildren();const card=document.createElement('section');card.className='card pad';card.innerHTML='<h2>Brief</h2><p></p><h2>还没有模型</h2><p>先明确需求，再导入模型并准备打印。</p>'; $('p',card).textContent=project.brief||'请完善作品需求。';content.append(card)}
   $$('button').filter(b=>/^准备打印$/.test(text(b))).forEach(b=>{b.disabled=true;b.title='尚未导入模型，不能准备打印'});
 }
 $$('.search').filter(x=>!x.matches('input')).forEach(el=>{el.innerHTML='<input aria-label="搜索作品" placeholder="搜索作品…" style="border:0;background:transparent;color:inherit;font:inherit;width:100%">';$('input',el).addEventListener('input',e=>{const cards=$$('.project-card');cards.forEach(c=>c.hidden=!text(c).toLowerCase().includes(e.target.value.toLowerCase()));let empty=$('#project-empty');if(!empty){empty=document.createElement('p');empty.id='project-empty';empty.className='proto-result';empty.textContent='没有匹配的作品';$('.content')?.append(empty)}empty.hidden=cards.some(c=>!c.hidden)})});
 match('button',/^编辑$/,()=>modal('编辑示例作品','修改保存在当前浏览器。',[{label:'名称',name:'name',value:read('projectName','相机快装板 V4'),required:true}],d=>{save('projectName',d.name);$('h1').textContent=d.name},'保存'));
 if(file==='project.html'&&read('projectName',null)&&!location.search)$('h1').textContent=read('projectName');
 const plans=['平衡 · 0.20 mm','精细 · 0.12 mm','快速 · 0.28 mm'];
 const currentPlan=()=>{const value=read('plan',plans[0]);return plans.includes(value)?value:plans[0]};
 function showPlan(){if(file!=='print-prep.html')return;const el=$('#selected-plan');if(el)el.textContent=currentPlan();const metric=$('.metric').find(x=>text($('.k',x))==='层高');if(metric){const v=$('.v',metric);if(v)v.textContent=currentPlan().split(' · ')[1]}}
 showPlan();
 match('button',/^换方案$/,()=>modal('切片方案','选择用于演示的方案，不运行真实切片。',[{label:'方案',name:'plan',options:plans,value:currentPlan()}],d=>{save('plan',d.plan);showPlan();status('已选用 '+d.plan)},'使用'));
 match('button',/^确认并派发/,()=>modal('确认模拟打印','相机快装板 V4 · 第 4 件\n设备：X1 Carbon\n材料：PETG 黑 / AMS 1\n方案：'+currentPlan()+'\n此操作仅增加本地演示记录，不向设备发送文件。',[],()=>{save('print',{state:'queued',plan:currentPlan(),at:new Date().toISOString()});go('devices.html?queued=1')},'确认加入演示队列'));
 if(file==='devices.html'&&read('print',null)){const notice=document.createElement('div');notice.className='card pad';notice.setAttribute('role','status');notice.textContent='本地演示队列：相机快装板 V4 · 第 4 件待打印 · '+(read('print',{}).plan||'未记录方案')+'，未向真实设备派发。';$('.content')?.prepend(notice)}
 match('button',/^暂停$|^继续$/,b=>modal(text(b)+'演示任务？','仅改变当前界面的演示状态，不控制打印机。',[],()=>{b.textContent=text(b)==='暂停'?'继续':'暂停';status('演示任务状态已更新')},'确认'));
 match('button',/^添加设备$/,()=>modal('添加演示设备','不搜索局域网，也不保存真实访问码。',[{label:'设备名称',name:'name',required:true},{label:'演示 IP',name:'ip',value:'192.168.1.100',required:true}],d=>{save('device',{name:d.name,ip:d.ip});const card=document.createElement('div');card.className='card pad';card.textContent=d.name+' · '+d.ip+' · 演示设备（未连接）';$('.content')?.prepend(card)},'添加'));
 match('button',/^盘点 AMS$/,()=>modal('AMS 示例盘点','槽位 1：PETG 黑 · 820 g\n槽位 2：PLA 白 · 450 g\n数据为界面样例，不来自实时设备。'));
 match('button',/^登记新耗材$/,()=>modal('登记本地耗材','仅保存当前浏览器中的示例记录。',[{label:'名称',name:'name',required:true},{label:'剩余重量（g）',name:'weight',type:'number',min:1,max:10000,required:true}],d=>{const materials=read('materials',[]);materials.push(d);save('materials',materials);location.reload()},'登记'));
 if(file==='materials.html')read('materials',[]).forEach(m=>{let card=document.createElement('div');card.className='card pad';card.textContent=m.name+' · '+m.weight+' g · 本地登记';$('.content')?.prepend(card)});
 match('button',/^移除$/,b=>modal('从购物清单移除？','只移除当前示例条目。',[],()=>{b.closest('.trow')?.remove();status('已移除示例条目')},'移除'));
 match('button',/^加入清单$/,b=>modal('加入本地购物清单？','PETG 黑 · 1 卷\n原型不会下单。',[],()=>{const list=read('shopping',[]);list.push('PETG 黑 · 1 卷');save('shopping',list);const card=b.closest('.confirm-card');if(card){card.textContent='已加入本地清单 · 未下单'}status('已加入本地清单')},'加入'));
 match('button',/^标记$/,b=>{save('materialDowngraded',true);const card=b.closest('.confirm-card');if(card){card.textContent='PLA 橙 · 已标记为非外观件专用（本地示例）';const undo=document.createElement('button');undo.className='btn';undo.textContent='撤销';link(undo,()=>{save('materialDowngraded',false);location.reload()});card.append(undo)}});
 match('button',/^忽略$/,b=>{b.closest('.confirm-card')?.remove();status('已忽略此建议')});
 match('button',/^发送$/,b=>{const composer=b.closest('.composer'),input=$('textarea',composer),message=input?.value.trim();if(!message){input?.focus();return}const chat=$('.chat-scroll')||$('.chat');if(!chat)return;const user=document.createElement('div');user.className='msg user';user.innerHTML='<div class="who">你</div><div class="bubble"></div>';$ ('.bubble',user).textContent=message;chat.append(user);input.value='';const response=document.createElement('div');response.className='msg ai';response.innerHTML='<div class="who">Advisor · 本地演示</div><div class="bubble">已记录这条示例消息。当前未连接模型服务，不会生成或执行设备指令。</div>';chat.append(response);chat.scrollTop=chat.scrollHeight});
 match('button',/^新对话$/,()=>modal('开始新对话？','当前页面的演示对话将清空。',[],()=>{const c=$('.chat-scroll');if(c)c.replaceChildren()},'开始'));
 match('button',/^@ 引用/,b=>modal('引用作品','给消息附加当前作品名称。',[{label:'作品',name:'project',options:['相机快装板 V4',...projects.map(p=>p.name)]}],d=>{const input=$('textarea',b.closest('.composer'));if(input)input.value+=' @'+d.project},'引用'));
 match('button',/^导出 CSV$/,()=>{const rows=$$('.table .trow').map(r=>[...r.children].map(c=>'"'+text(c).replace(/"/g,'""')+'"').join(','));download('layerly-sample-history.csv','\uFEFF'+rows.join('\r\n'),'text/csv')});
 match('button',/^导出打印包$/,()=>download('layerly-sample-print-package.json',JSON.stringify({prototype:true,project:'相机快装板 V4',plan:currentPlan(),modelIncluded:false},null,2)));
 match('button',/^详情$/,b=>modal('打印记录详情',text(b.closest('.trow'))+'\n示例记录，不来自设备。'));
 match('button',/^查看全部/,()=>status('当前展示此原型包含的全部历史样例'));
 if(file==='model-viewer.html'){
   const model=$('.stage-model'),fill=$('.slice-ctl .fill'),label=$('.slice-ctl > .num');let layer=114,angle=0,timer;
   const slider=document.createElement('input');slider.type='range';slider.min=1;slider.max=184;slider.value=layer;slider.setAttribute('aria-label','模型层数');$('.slice-track').replaceChildren(slider);
   const render=()=>{slider.value=layer;label.textContent=`L ${layer} / 184`;model.style.transform=`rotate(${angle}deg)`;model.style.clipPath=`inset(${100-layer/184*100}% 0 0 0)`};slider.oninput=()=>{layer=Number(slider.value);render()};
   $$('button[title]').forEach(b=>{if(b.title==='线框 / 实体')link(b,()=>{model.style.opacity=model.style.opacity==='0.45'?'1':'0.45';b.setAttribute('aria-pressed',model.style.opacity==='0.45')});if(b.title==='剖层')link(b,()=>{layer=layer===184?92:184;render()});if(b.title==='复位视角')link(b,()=>{angle=0;layer=184;render()})});
   match('button',/^播放层积$|^暂停层积$/,b=>{if(timer){clearInterval(timer);timer=null;b.textContent='播放层积'}else{if(layer>=184)layer=1;b.textContent='暂停层积';timer=setInterval(()=>{layer++;render();if(layer>=184){clearInterval(timer);timer=null;b.textContent='播放层积'}},60)}});
   model.style.cursor='grab';model.style.touchAction='none';let x;model.addEventListener('pointerdown',e=>{x=e.clientX;model.setPointerCapture(e.pointerId)});model.addEventListener('pointermove',e=>{if(x===undefined)return;angle+=e.clientX-x;x=e.clientX;render()});['pointerup','pointercancel','lostpointercapture'].forEach(type=>model.addEventListener(type,()=>x=undefined));window.addEventListener('pagehide',()=>clearInterval(timer));
 }
 match('button',/^绑定访问码$/,()=>modal('绑定演示设备','请勿输入真实设备访问码。',[{label:'演示访问码（demo-code）',name:'code',required:true}],d=>{if(d.code!=='demo-code'){status('请输入 demo-code');return false}status('演示绑定完成 · 未连接设备')},'绑定'));
 match('button',/^重新搜索$/,()=>status('已刷新演示设备列表 · 未扫描网络'));
 match('button',/^下一步：配置 AI$/,()=>modal('配置 AI（原型）','可以跳过，之后再设置。模型和设备均不会连接。',[{label:'演示提供商',name:'provider',options:['暂不配置','OpenAI','Ollama']}],d=>{save('provider',d.provider);modal('完成设置','本地示例工作区已准备好。',[],()=>go('dashboard.html'),'打开工作台')},'完成'));
})();
