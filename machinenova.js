// MachineNova — interactions

// ── Tab switching (Agents section)
document.querySelectorAll('.cx-tab').forEach(tab => {
  tab.addEventListener('click', function () {
    const pane = this.dataset.tab;
    const parent = this.closest('.cx-plat-text');
    parent.querySelectorAll('.cx-tab').forEach(t => {
      t.classList.remove('cx-tab--active', 'active');
    });
    parent.querySelectorAll('.cx-pane').forEach(p => {
      p.classList.remove('cx-pane--active', 'active');
    });
    this.classList.add('cx-tab--active');
    const target = document.getElementById('tab-' + pane);
    if (target) target.classList.add('cx-pane--active');
  });
});

// ── FAQ accordion
document.querySelectorAll('.cx-faq-q').forEach(btn => {
  btn.addEventListener('click', function () {
    const item = this.closest('.cx-faq');
    const isOpen = item.classList.contains('open');
    document.querySelectorAll('.cx-faq.open').forEach(i => i.classList.remove('open'));
    if (!isOpen) item.classList.add('open');
  });
});

// ── Mobile dropdown
document.querySelectorAll('.nav-dropdown').forEach(item => {
  const trigger = item.querySelector('.dropdown-trigger');
  if (trigger) {
    trigger.addEventListener('click', e => {
      if (window.innerWidth <= 768) {
        e.preventDefault();
        item.classList.toggle('open');
      }
    });
  }
});

// ── Animate bars on scroll
const barObs = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.querySelectorAll('.cx-bar-fill').forEach(bar => {
        const w = bar.style.width;
        bar.style.width = '0';
        setTimeout(() => {
          bar.style.transition = 'width 1s cubic-bezier(0.4,0,0.2,1)';
          bar.style.width = w;
        }, 80);
      });
      barObs.unobserve(entry.target);
    }
  });
}, { threshold: 0.3 });
document.querySelectorAll('.cx-plat-card').forEach(c => barObs.observe(c));

// ── Scroll reveal
const revObs = new IntersectionObserver(entries => {
  entries.forEach((entry, i) => {
    if (entry.isIntersecting) {
      setTimeout(() => {
        entry.target.style.opacity = '1';
        entry.target.style.transform = 'translateY(0)';
      }, i * 70);
      revObs.unobserve(entry.target);
    }
  });
}, { threshold: 0.1, rootMargin: '0px 0px -40px 0px' });

document.querySelectorAll('.cx-tc, .cx-plat-card').forEach(el => {
  el.style.opacity = '0';
  el.style.transform = 'translateY(20px)';
  el.style.transition = 'all 0.5s ease';
  revObs.observe(el);
});

// ── Contact form
const cxForm = document.getElementById('cx-form');
if (cxForm) {
  cxForm.addEventListener('submit', e => {
    e.preventDefault();
    const btn = cxForm.querySelector('.cx-form-btn');
    const orig = btn.textContent;
    btn.textContent = 'Message Sent ✓';
    btn.style.background = '#16a34a';
    btn.style.color = '#fff';
    setTimeout(() => {
      btn.textContent = orig;
      btn.style.background = '';
      btn.style.color = '';
      cxForm.reset();
    }, 3000);
  });
}
