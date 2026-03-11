// Smooth PHP-like scrolling with WordPress lightness effect
const hamburger=document.getElementById('hamburger');const navMenu=document.getElementById('navMenu');let scrollVelocity=0;let lastScrollY=0;let ticking=false;

// Mobile menu with smooth transitions
hamburger.addEventListener('click',()=>{navMenu.classList.toggle('active');hamburger.classList.toggle('active');document.body.style.overflow=navMenu.classList.contains('active')?'hidden':'auto'});

document.querySelectorAll('.nav-menu a').forEach(link=>{link.addEventListener('click',()=>{navMenu.classList.remove('active');hamburger.classList.remove('active');document.body.style.overflow='auto'})});

// Smooth anchor scrolling with easing
document.querySelectorAll('a[href^="#"]').forEach(anchor=>{anchor.addEventListener('click',function(e){e.preventDefault();const target=document.querySelector(this.getAttribute('href'));if(target){const targetPos=target.getBoundingClientRect().top+window.scrollY;const startPos=window.scrollY;const distance=targetPos-startPos;const duration=1000;let start=null;const easeInOutCubic=(t,b,c,d)=>{t/=d/2;if(t<1)return c/2*t*t*t+b;t-=2;return c/2*(t*t*t+2)+b};const scroll=(timestamp)=>{if(!start)start=timestamp;const progress=timestamp-start;const ease=easeInOutCubic(progress,startPos,distance,duration);window.scrollTo(0,ease);if(progress<duration){requestAnimationFrame(scroll)}};requestAnimationFrame(scroll)}})});

// Advanced FAQ accordion with smooth height animation
document.querySelectorAll('.faq-question').forEach(question=>{question.addEventListener('click',()=>{const faqItem=question.parentElement;const isActive=faqItem.classList.contains('active');const answer=faqItem.querySelector('.faq-answer');document.querySelectorAll('.faq-item').forEach(item=>{if(item!==faqItem){item.classList.remove('active');const ans=item.querySelector('.faq-answer');ans.style.maxHeight='0px'}});if(!isActive){faqItem.classList.add('active');answer.style.maxHeight=answer.scrollHeight+'px';answer.addEventListener('transitionend',()=>{answer.style.maxHeight='none'},{'once':true})}})});

// Intersection Observer with staggered animations
const observerOptions={threshold:0.15,rootMargin:'0px 0px -100px 0px'};const observer=new IntersectionObserver((entries)=>{entries.forEach((entry,index)=>{if(entry.isIntersecting){setTimeout(()=>{entry.target.classList.add('visible')},index*50)}})},observerOptions);

document.querySelectorAll('.features h2,.features-intro,.feature-card,.support-label,.support h2,.support p,.person-img,.standout h2,.section-subtitle,.standout-item,.testimonials h2,.testimonials-subtitle,.testimonial-card,.faqs h2,.faqs-subtitle,.faq-item').forEach(el=>{observer.observe(el)});

// Smooth header with blur effect on scroll
let lastScroll=0;const header=document.querySelector('.header');window.addEventListener('scroll',()=>{const currentScroll=window.pageYOffset;const scrollDelta=Math.abs(currentScroll-lastScroll);if(scrollDelta>5){if(currentScroll>100){header.style.background='rgba(0,0,0,0.98)';header.style.backdropFilter='blur(12px)';header.style.boxShadow='0 8px 32px rgba(0,102,255,0.15)'}else{header.style.background='#000';header.style.boxShadow='none'}}lastScroll=currentScroll},{'passive':true});

// Smooth navigation active state
window.addEventListener('scroll',()=>{let current='';const sections=document.querySelectorAll('section[id]');sections.forEach(section=>{const sectionTop=section.offsetTop;if(pageYOffset>=sectionTop-200){current=section.getAttribute('id')}});document.querySelectorAll('.nav-menu a').forEach(link=>{link.classList.remove('active');if(link.getAttribute('href')===`#${current}`){link.classList.add('active')}})},{'passive':true});

// Button interactions with ripple effect
document.querySelectorAll('.btn,.cta-btn').forEach(btn=>{btn.addEventListener('click',function(e){const text=this.textContent.toLowerCase();if(text.includes('download')){e.preventDefault();showNotification('Download functionality would be implemented here!')}else if(text.includes('demo')||text.includes('chat')){e.preventDefault();showNotification('Demo booking form would open here!')}});btn.addEventListener('mouseenter',function(){this.style.transform='translateY(-3px)';this.style.boxShadow='0 8px 24px rgba(0,102,255,0.4)'});btn.addEventListener('mouseleave',function(){this.style.transform='translateY(0)';this.style.boxShadow=''})});

// Smooth parallax effect on hero
window.addEventListener('scroll',()=>{const scrolled=window.pageYOffset;const heroBox=document.querySelector('.hero-box');if(heroBox&&scrolled<800){const parallaxValue=scrolled*0.08;heroBox.style.transform=`translateY(${parallaxValue}px)`;heroBox.style.opacity=Math.max(0.5,1-(scrolled/1000))}},{'passive':true});

// Lazy load images with fade-in
const imageObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){const img=entry.target;img.src=img.dataset.src||img.src;img.style.opacity='0';img.style.transition='opacity 0.6s ease';setTimeout(()=>{img.style.opacity='1'},50);imageObserver.unobserve(img)}})},{threshold:0.1});

document.querySelectorAll('img[data-src]').forEach(img=>imageObserver.observe(img));

// Smooth card hover effects
document.querySelectorAll('.feature-card,.testimonial-card,.standout-item').forEach(card=>{card.addEventListener('mouseenter',function(){this.style.transform='translateY(-8px) scale(1.02)';this.style.boxShadow='0 20px 50px rgba(0,102,255,0.25)';this.style.transition='all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)'});card.addEventListener('mouseleave',function(){this.style.transform='translateY(0) scale(1)';this.style.boxShadow='';this.style.transition='all 0.3s ease'})});

// Smooth icon animations
document.querySelectorAll('.standout-icon').forEach(icon=>{icon.addEventListener('mouseenter',function(){this.style.transform='scale(1.15) rotate(8deg)';this.style.transition='transform 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)'});icon.addEventListener('mouseleave',function(){this.style.transform='scale(1) rotate(0deg)'})});

// Notification system
function showNotification(message){const notification=document.createElement('div');notification.textContent=message;notification.style.cssText=`position:fixed;top:20px;right:20px;background:linear-gradient(135deg,#0066FF,#0052cc);color:#fff;padding:16px 24px;border-radius:12px;font-family:'Inter',sans-serif;font-weight:600;z-index:10000;box-shadow:0 8px 24px rgba(0,102,255,0.4);animation:slideInRight 0.4s ease;backdrop-filter:blur(10px)`;document.body.appendChild(notification);setTimeout(()=>{notification.style.animation='slideOutRight 0.4s ease';setTimeout(()=>notification.remove(),400)},3000)}

// Add animation keyframes
const style=document.createElement('style');style.textContent=`@keyframes slideInRight{from{opacity:0;transform:translateX(100px)}to{opacity:1;transform:translateX(0)}}@keyframes slideOutRight{from{opacity:1;transform:translateX(0)}to{opacity:0;transform:translateX(100px)}}@keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-20px)}}@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.7}}`;document.head.appendChild(style);

// Smooth form interactions
document.querySelectorAll('.form-group input,.form-group textarea').forEach(input=>{input.addEventListener('focus',function(){this.parentElement.style.borderColor='var(--blue)';this.parentElement.style.boxShadow='0 0 0 3px rgba(0,102,255,0.1)';this.parentElement.style.transition='all 0.3s ease'});input.addEventListener('blur',function(){this.parentElement.style.borderColor='var(--border)';this.parentElement.style.boxShadow='none'})});

// Contact form with smooth validation
const contactForm=document.getElementById('contactForm');if(contactForm){contactForm.addEventListener('submit',(e)=>{e.preventDefault();const name=document.getElementById('name').value.trim();const email=document.getElementById('email').value.trim();const message=document.getElementById('message').value.trim();if(!name||!email||!message){showNotification('Please fill in all fields');return}const emailRegex=/^[^\s@]+@[^\s@]+\.[^\s@]+$/;if(!emailRegex.test(email)){showNotification('Please enter a valid email address');return}showNotification('Thank you! We will get back to you soon.');contactForm.reset()})}

// Smooth page load animation
window.addEventListener('load',()=>{document.body.style.opacity='1';document.querySelectorAll('.hero-label,.hero h1,.hero-desc,.hero-btns').forEach((el,index)=>{el.style.animationDelay=`${0.2+(index*0.15)}s`})});

// Performance: RequestAnimationFrame for smooth scrolling
let scrollTicking=false;window.addEventListener('scroll',()=>{if(!scrollTicking){requestAnimationFrame(()=>{const scrolled=window.pageYOffset;document.querySelectorAll('.feature-card').forEach((card,index)=>{const speed=0.5+index*0.1;card.style.transform=`translateY(${scrolled*speed*0.005}px)`});scrollTicking=false});scrollTicking=true}},{'passive':true});

// Smooth resize handling
let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{document.querySelectorAll('.faq-item.active').forEach(item=>{const answer=item.querySelector('.faq-answer');answer.style.maxHeight=answer.scrollHeight+'px'})},250)});

// Preload critical resources
window.addEventListener('load',()=>{const links=document.querySelectorAll('a[href]');links.forEach(link=>{const href=link.getAttribute('href');if(href&&!href.startsWith('#')&&!href.startsWith('http')){const prefetch=document.createElement('link');prefetch.rel='prefetch';prefetch.href=href;document.head.appendChild(prefetch)}})});

// Smooth transitions on page visibility
document.addEventListener('visibilitychange',()=>{if(document.hidden){document.querySelectorAll('*').forEach(el=>{el.style.transition='none'})}else{setTimeout(()=>{document.querySelectorAll('*').forEach(el=>{el.style.transition=''})},100)}});

