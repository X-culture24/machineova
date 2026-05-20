// MachineNova — interactions

// FAQ accordion
document.querySelectorAll('.cx-faq-q').forEach(btn => {
  btn.addEventListener('click', function () {
    const item = this.closest('.cx-faq');
    const isOpen = item.classList.contains('open');
    document.querySelectorAll('.cx-faq.open').forEach(i => i.classList.remove('open'));
    if (!isOpen) item.classList.add('open');
  });
});

// Tab switching
document.querySelectorAll('.cx-tab').forEach(tab => {
  tab.addEventListener('click', function () {
    const pane = this.dataset.tab;
    const parent = this.closest('.cx-plat-text') || this.closest('section');
    if (!parent) return;
    parent.querySelectorAll('.cx-tab').forEach(t => t.classList.remove('active'));
    parent.querySelectorAll('.cx-pane').forEach(p => p.classList.remove('active'));
    this.classList.add('active');
    const target = document.getElementById('tab-' + pane);
    if (target) target.classList.add('active');
  });
});

// Mobile dropdown
document.querySelectorAll('.nav-dropdown').forEach(item => {
  const trigger = item.querySelector('.dropdown-trigger');
  if (trigger) {
    trigger.addEventListener('click', function (e) {
      if (window.innerWidth <= 768) {
        e.preventDefault();
        item.classList.toggle('open');
      }
    });
  }
});

// Animate bar fills on scroll
const barObserver = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.querySelectorAll('.cx-bar-fill, .cx-cmd-fill').forEach(bar => {
        const w = bar.style.width;
        bar.style.width = '0';
        setTimeout(() => {
          bar.style.transition = 'width 1s cubic-bezier(0.4,0,0.2,1)';
          bar.style.width = w;
        }, 80);
      });
      barObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.3 });
document.querySelectorAll('.cx-data-card, .cx-cmd-card').forEach(c => barObserver.observe(c));

// Scroll reveal
const revealObs = new IntersectionObserver(entries => {
  entries.forEach((entry, i) => {
    if (entry.isIntersecting) {
      setTimeout(() => {
        entry.target.style.opacity = '1';
        entry.target.style.transform = 'translateY(0)';
      }, i * 60);
      revealObs.unobserve(entry.target);
    }
  });
}, { threshold: 0.08, rootMargin: '0px 0px -40px 0px' });

document.querySelectorAll('.cx-ov-card, .cx-for-card, .cx-case-card, .cx-sec-card, .cx-cs-item').forEach(el => {
  el.style.opacity = '0';
  el.style.transform = 'translateY(16px)';
  el.style.transition = 'all 0.5s ease';
  revealObs.observe(el);
});

// Contact form
const homeForm = document.getElementById('cx-home-form');
if (homeForm) {
  homeForm.addEventListener('submit', e => {
    e.preventDefault();
    const btn = homeForm.querySelector('button[type="submit"]');
    const orig = btn.innerHTML;
    btn.textContent = 'Request Sent';
    btn.style.background = '#16a34a';
    setTimeout(() => { btn.innerHTML = orig; btn.style.background = ''; homeForm.reset(); }, 3000);
  });
}
