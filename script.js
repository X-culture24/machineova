// Smooth PHP-like scrolling with WordPress lightness effect
const hamburger=document.getElementById('hamburger');const navMenu=document.getElementById('navMenu');let scrollVelocity=0;let lastScrollY=0;let ticking=false;

// Mobile menu with smooth transitions
hamburger.addEventListener('click',()=>{navMenu.classList.toggle('active');hamburger.classList.toggle('active');document.body.style.overflow=navMenu.classList.contains('active')?'hidden':'auto'});

document.querySelectorAll('.nav-menu a').forEach(link=>{link.addEventListener('click',()=>{navMenu.classList.remove('active');hamburger.classList.remove('active');document.body.style.overflow='auto'})});

// Smooth anchor scrolling with easing
document.querySelectorAll('a[href^="#"]').forEach(anchor=>{anchor.addEventListener('click',function(e){e.preventDefault();const target=document.querySelector(this.getAttribute('href'));if(target){const targetPos=target.getBoundingClientRect().top+window.scrollY;const startPos=window.scrollY;const distance=targetPos-startPos;const duration=1000;let start=null;const easeInOutCubic=(t,b,c,d)=>{t/=d/2;if(t<1)return c/2*t*t*t+b;t-=2;return c/2*(t*t*t+2)+b};const scroll=(timestamp)=>{if(!start)start=timestamp;const progress=timestamp-start;const ease=easeInOutCubic(progress,startPos,distance,duration);window.scrollTo(0,ease);if(progress<duration){requestAnimationFrame(scroll)}};requestAnimationFrame(scroll)}})});

// Advanced FAQ accordion with smooth height animation - FIXED
document.querySelectorAll('.faq-question').forEach(question=>{question.addEventListener('click',function(e){e.preventDefault();e.stopPropagation();const faqItem=this.closest('.faq-item');if(!faqItem)return;const isActive=faqItem.classList.contains('active');const answer=faqItem.querySelector('.faq-answer');if(!answer)return;document.querySelectorAll('.faq-item').forEach(item=>{if(item!==faqItem&&item.classList.contains('active')){item.classList.remove('active');const ans=item.querySelector('.faq-answer');if(ans){ans.style.maxHeight='0px';ans.style.opacity='0'}}});if(!isActive){faqItem.classList.add('active');answer.style.maxHeight=answer.scrollHeight+'px';answer.style.opacity='1';answer.style.display='block'}else{faqItem.classList.remove('active');answer.style.maxHeight='0px';answer.style.opacity='0'}})});

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



// Animated Counter for Stats
function animateCounter(element){const target=parseInt(element.getAttribute('data-target'));const duration=2000;const increment=target/duration*10;let current=0;const timer=setInterval(()=>{current+=increment;if(current>=target){element.textContent=target.toLocaleString()+(element.parentElement.querySelector('p').textContent.includes('Rate')?'%':'+');clearInterval(timer)}else{element.textContent=Math.floor(current).toLocaleString()}},10)}const statsObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){const statNumbers=entry.target.querySelectorAll('.stat-number');statNumbers.forEach(num=>animateCounter(num));statsObserver.unobserve(entry.target)}})},{threshold:0.5});const impactStats=document.querySelector('.impact-stats');if(impactStats){statsObserver.observe(impactStats)}


// Lazy Text Animation Observer
const lazyTextObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');lazyTextObserver.unobserve(entry.target)}})},{threshold:0.2,rootMargin:'0px 0px -50px 0px'});document.querySelectorAll('.lazy-text').forEach(el=>{lazyTextObserver.observe(el)});

// Lazy Heading Word Animation
document.querySelectorAll('.lazy-heading').forEach(heading=>{const words=heading.querySelectorAll('.word');words.forEach((word,index)=>{word.style.animationDelay=`${0.1+(index*0.1)}s`})});

// Feature Stats Counter Animation
const statsObserver2=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.style.animation='scaleIn 0.5s ease forwards';statsObserver2.unobserve(entry.target)}})},{threshold:0.5});document.querySelectorAll('.stat-badge,.feature-metric').forEach(el=>{el.style.opacity='0';el.style.transform='scale(0.8)';statsObserver2.observe(el)});const style2=document.createElement('style');style2.textContent='@keyframes scaleIn{to{opacity:1;transform:scale(1)}}';document.head.appendChild(style2);


// Scroll Progress Indicator
const scrollProgress=document.createElement('div');scrollProgress.className='scroll-progress';document.body.appendChild(scrollProgress);window.addEventListener('scroll',()=>{const winScroll=document.body.scrollTop||document.documentElement.scrollTop;const height=document.documentElement.scrollHeight-document.documentElement.clientHeight;const scrolled=(winScroll/height)*100;scrollProgress.style.width=scrolled+'%'},{'passive':true});

// Mouse tracking for grid hover effect
const standoutGrid=document.querySelector('.standout-grid-pro');if(standoutGrid){standoutGrid.addEventListener('mousemove',(e)=>{const rect=standoutGrid.getBoundingClientRect();const x=((e.clientX-rect.left)/rect.width)*100;const y=((e.clientY-rect.top)/rect.height)*100;standoutGrid.style.setProperty('--mouse-x',x+'%');standoutGrid.style.setProperty('--mouse-y',y+'%')})}

// Enhanced card interactions with 3D tilt
document.querySelectorAll('.standout-card,.feature-card,.why-item').forEach(card=>{card.addEventListener('mousemove',(e)=>{const rect=card.getBoundingClientRect();const x=e.clientX-rect.left;const y=e.clientY-rect.top;const centerX=rect.width/2;const centerY=rect.height/2;const rotateX=(y-centerY)/20;const rotateY=(centerX-x)/20;card.style.transform=`perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-8px) scale(1.02)`;card.style.transition='transform 0.1s ease'});card.addEventListener('mouseleave',()=>{card.style.transform='perspective(1000px) rotateX(0) rotateY(0) translateY(0) scale(1)';card.style.transition='transform 0.5s cubic-bezier(0.34, 1.56, 0.64, 1)'})});

// Smooth image loading with blur effect
document.querySelectorAll('.about-img,.impact-img,.person-img').forEach(img=>{img.style.filter='blur(10px)';img.style.transition='filter 0.8s ease';img.addEventListener('load',()=>{setTimeout(()=>{img.style.filter='blur(0)'},100)})});

// Enhanced section visibility animations
const sectionObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');entry.target.style.transitionDelay='0.2s'}})},{threshold:0.1,rootMargin:'0px 0px -80px 0px'});document.querySelectorAll('.about-section').forEach(section=>{sectionObserver.observe(section)});

// Floating badge animation trigger
const badgeObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.querySelectorAll('.floating-badge').forEach((badge,index)=>{badge.style.animationDelay=`${index*0.3}s`})}})},{threshold:0.3});document.querySelectorAll('.image-badge-group').forEach(group=>{badgeObserver.observe(group)});

// Smooth stat icon animations
document.querySelectorAll('.stat-icon').forEach((icon,index)=>{icon.style.opacity='0';icon.style.transform='scale(0) rotate(-180deg)';icon.style.transition='all 0.6s cubic-bezier(0.34, 1.56, 0.64, 1)';setTimeout(()=>{const iconObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){setTimeout(()=>{entry.target.style.opacity='1';entry.target.style.transform='scale(1) rotate(0)'},index*100);iconObserver.unobserve(entry.target)}})},{threshold:0.5});iconObserver.observe(icon)},100)});

// Enhanced button hover with scale
document.querySelectorAll('.btn-primary,.btn-secondary,.btn-outline').forEach(btn=>{btn.addEventListener('mouseenter',function(){this.style.transform='translateY(-4px) scale(1.05)';this.style.transition='all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)'});btn.addEventListener('mouseleave',function(){this.style.transform='translateY(0) scale(1)'})});

// Smooth badge animations on card hover
document.querySelectorAll('.standout-card').forEach(card=>{const badges=card.querySelectorAll('.badge-blue');card.addEventListener('mouseenter',()=>{badges.forEach((badge,index)=>{setTimeout(()=>{badge.style.transform='translateY(-5px) scale(1.08)';badge.style.transition='all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)'},index*50)})});card.addEventListener('mouseleave',()=>{badges.forEach(badge=>{badge.style.transform='translateY(0) scale(1)'})})});

// Performance optimization: Debounce scroll events
function debounce(func,wait){let timeout;return function executedFunction(...args){const later=()=>{clearTimeout(timeout);func(...args)};clearTimeout(timeout);timeout=setTimeout(later,wait)}}

// Smooth window resize handling
const debouncedResize=debounce(()=>{document.querySelectorAll('.feature-card,.testimonial-card').forEach(card=>{card.style.transition='all 0.3s ease'})},250);window.addEventListener('resize',debouncedResize);

// Add smooth reveal for commitment list items
document.querySelectorAll('.commitment-list li,.vision-list li').forEach((item,index)=>{item.style.opacity='0';item.style.transform='translateX(-30px)';const listObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){setTimeout(()=>{entry.target.style.opacity='1';entry.target.style.transform='translateX(0)';entry.target.style.transition='all 0.6s cubic-bezier(0.34, 1.56, 0.64, 1)'},index*100);listObserver.unobserve(entry.target)}})},{threshold:0.3});listObserver.observe(item)});

// Enhanced metric bar animations
document.querySelectorAll('.metric-bar').forEach((bar,index)=>{const metricObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){setTimeout(()=>{entry.target.style.animation='barGrow 1.5s ease forwards'},index*150);metricObserver.unobserve(entry.target)}})},{threshold:0.5});metricObserver.observe(bar)});

// Smooth tech item reveals
document.querySelectorAll('.tech-item').forEach((item,index)=>{item.style.opacity='0';item.style.transform='translateX(-40px)';const techObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){setTimeout(()=>{entry.target.style.opacity='1';entry.target.style.transform='translateX(0)';entry.target.style.transition='all 0.7s cubic-bezier(0.34, 1.56, 0.64, 1)'},index*120);techObserver.unobserve(entry.target)}})},{threshold:0.3});techObserver.observe(item)});

// GPU acceleration for smooth animations
document.querySelectorAll('.feature-card,.testimonial-card,.standout-card,.btn').forEach(el=>{el.style.willChange='transform';el.style.transform='translateZ(0)'});

// Cleanup will-change after animations
setTimeout(()=>{document.querySelectorAll('[style*="will-change"]').forEach(el=>{el.style.willChange='auto'})},3000);


// Why Grid and Tech Features Animation Observer
const whyObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');whyObserver.unobserve(entry.target)}})},{threshold:0.2,rootMargin:'0px 0px -50px 0px'});document.querySelectorAll('.why-item,.tech-item').forEach(item=>{whyObserver.observe(item)});

// Enhanced image hover effects
document.querySelectorAll('.about-image').forEach(img=>{img.addEventListener('mouseenter',function(){const badge=this.querySelector('.image-badge-group');if(badge){badge.style.transform='translateX(-10px) scale(1.1)';badge.style.transition='all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)'}});img.addEventListener('mouseleave',function(){const badge=this.querySelector('.image-badge-group');if(badge){badge.style.transform='translateX(0) scale(1)'}})});

// Smooth scroll to top on page load
window.addEventListener('load',()=>{window.scrollTo({top:0,behavior:'instant'});setTimeout(()=>{document.body.style.opacity='1'},50)});

// Enhanced parallax for about images
window.addEventListener('scroll',()=>{const scrolled=window.pageYOffset;document.querySelectorAll('.about-img').forEach((img,index)=>{if(img.getBoundingClientRect().top<window.innerHeight&&img.getBoundingClientRect().bottom>0){const speed=0.3+index*0.1;const yPos=-(scrolled*speed*0.05);img.style.transform=`translateY(${yPos}px) scale(1.1)`;img.style.transition='transform 0.1s ease'}})},{'passive':true});

// Magnetic effect for buttons
document.querySelectorAll('.btn-primary,.cta-btn').forEach(btn=>{btn.addEventListener('mousemove',(e)=>{const rect=btn.getBoundingClientRect();const x=e.clientX-rect.left-rect.width/2;const y=e.clientY-rect.top-rect.height/2;btn.style.transform=`translate(${x*0.1}px, ${y*0.1}px) scale(1.05)`;btn.style.transition='transform 0.1s ease'});btn.addEventListener('mouseleave',()=>{btn.style.transform='translate(0, 0) scale(1)';btn.style.transition='transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)'})});


// Lazy Text Animation on Scroll
const lazyTextObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');lazyTextObserver.unobserve(entry.target)}})},{threshold:0.2,rootMargin:'0px 0px -50px 0px'});document.querySelectorAll('.lazy-text').forEach(el=>{lazyTextObserver.observe(el)});

// Lazy Heading Word Animation
document.querySelectorAll('.lazy-heading').forEach(heading=>{const words=heading.querySelectorAll('.word');words.forEach((word,index)=>{word.style.animationDelay=`${0.1+(index*0.1)}s`})});

// Page Load Animation
window.addEventListener('load',()=>{document.body.style.opacity='1'});

// Section Fade In on Scroll
const sectionObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.style.opacity='1';sectionObserver.unobserve(entry.target)}})},{threshold:0.1});document.querySelectorAll('section').forEach(section=>{sectionObserver.observe(section)});


// ========================================
// LAZY TEXT ANIMATIONS - ALL PAGES
// ========================================

// Force all sections visible immediately
document.addEventListener('DOMContentLoaded',()=>{document.querySelectorAll('section').forEach(section=>{section.style.opacity='1';section.style.visibility='visible';section.style.display='block'});document.querySelectorAll('.lazy-text,.lazy-heading').forEach(el=>{el.style.opacity='1';el.style.visibility='visible'});document.querySelectorAll('.lazy-heading .word').forEach(word=>{word.style.opacity='1';word.style.visibility='visible';word.style.animation='wordFadeInUp 0.6s cubic-bezier(0.34,1.56,0.64,1) forwards'})});

// Lazy Text Observer for All Pages - TRIGGER ANIMATIONS ON SCROLL
const lazyTextObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');entry.target.style.opacity='1';entry.target.style.visibility='visible';entry.target.style.animation='fadeInUp 0.8s cubic-bezier(0.34,1.56,0.64,1) forwards';lazyTextObserver.unobserve(entry.target)}})},{threshold:0.05,rootMargin:'0px 0px -100px 0px'});

// Apply to all lazy text elements
setTimeout(()=>{document.querySelectorAll('.lazy-text,.section-header p,.feature-card h3,.standout-card h3,.security-card h3,.problem-card h3,.about-text p,.vision-list li,.commitment-list li,.feature-highlights li,.why-item h3,.why-item p,.tech-item h4,.tech-item p,.problem-desc,.stat-number,.testimonial-card p,.faq-question span,.pricing-highlight,.footer-col h4').forEach(el=>{el.classList.add('visible');el.style.opacity='1';el.style.visibility='visible';lazyTextObserver.observe(el)})},100);

// Lazy Heading Word Animation - ANIMATE WORDS
document.querySelectorAll('.lazy-heading').forEach(heading=>{const words=heading.querySelectorAll('.word');words.forEach((word,index)=>{word.style.animationDelay=`${0.1+(index*0.15)}s`;word.style.opacity='1';word.style.visibility='visible';word.style.animation='wordFadeInUp 0.6s cubic-bezier(0.34,1.56,0.64,1) forwards'})});

// Page Load Animation
window.addEventListener('load',()=>{document.body.style.opacity='1';document.body.style.visibility='visible'});

// Section Fade In on Scroll
const sectionObserver=new IntersectionObserver((entries)=>{entries.forEach(entry=>{if(entry.isIntersecting){entry.target.style.opacity='1';entry.target.style.visibility='visible';entry.target.style.animation='fadeInUp 0.8s cubic-bezier(0.34,1.56,0.64,1) forwards';sectionObserver.unobserve(entry.target)}})},{threshold:0.05,rootMargin:'0px 0px -100px 0px'});document.querySelectorAll('section').forEach(section=>{section.style.opacity='1';section.style.visibility='visible';sectionObserver.observe(section)});

// Animate cards on scroll
const cardObserver=new IntersectionObserver((entries)=>{entries.forEach((entry,index)=>{if(entry.isIntersecting){setTimeout(()=>{entry.target.style.opacity='1';entry.target.style.transform='translateY(0)';entry.target.style.animation='slideUp 0.8s cubic-bezier(0.34,1.56,0.64,1) forwards'},index*100);cardObserver.unobserve(entry.target)}})},{threshold:0.05,rootMargin:'0px 0px -100px 0px'});document.querySelectorAll('.feature-card,.standout-card,.security-card,.testimonial-card,.problem-card,.why-item,.tech-item').forEach(card=>{card.style.opacity='0';card.style.transform='translateY(30px)';card.style.transition='all 0.8s cubic-bezier(0.34,1.56,0.64,1)';cardObserver.observe(card)});
