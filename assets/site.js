document.addEventListener('scroll',()=>document.querySelector('header.top')?.classList.toggle('scrolled',scrollY>8),{passive:true});
document.querySelectorAll('.cmd button').forEach(b=>b.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(b.previousElementSibling.textContent.trim());b.textContent='Copied';setTimeout(()=>b.textContent='Copy',1400)}catch(e){}}));
