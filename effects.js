/* ================================================================
   MACHINENOVA — GLOBAL EFFECTS
   1. Page-load fade-in (WordPress/PHP style)
   2. Lazy text reveal on scroll
   3. Parallax on scroll
   4. Light/dark mode toggle
   5. Scroll progress bar
   ================================================================ */

(function () {
  'use strict';

  /* ── 1. PAGE LOAD FADE-IN ──────────────────────────────────────
     Body starts at opacity:0 (set in CSS).
     On DOMContentLoaded we add .page-loaded which transitions to 1.
     This gives the clean "page materialises" WordPress feel.
  ──────────────────────────────────────────────────────────────── */
  document.addEventListener('DOMContentLoaded', function () {
    // Small RAF delay so the browser has painted before fading in
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        document.body.classList.add('page-loaded');
      });
    });

    initReveal();
    initParallax();
    initProgressBar();
    initSmoothScroll();
  });


  /* ── 2. LAZY REVEAL ON SCROLL ──────────────────────────────────
     Any element with class "reveal" will animate in when it enters
     the viewport. Add "reveal--left", "reveal--right", "reveal--scale"
     for directional variants.
     Wrap siblings in "reveal-group" for staggered delays.
  ──────────────────────────────────────────────────────────────── */
  function initReveal() {
    // Auto-tag common content elements if not already tagged
    var autoTargets = [
      // Homepage
      '.cx-trust-strip',
      '.cx-overview-head h2', '.cx-overview-head p',
      '.cx-ov-card',
      '.cx-about-heading', '.cx-about-body',
      '.cx-about-photos .cx-photo-wrap',
      '.cx-for-head h2', '.cx-for-card',
      '.cx-spotlight-text h2', '.cx-spotlight-text p', '.cx-spotlight-list',
      '.cx-cmd-card',
      '.cx-sec-text h2', '.cx-sec-text p', '.cx-sec-pillar',
      '.cx-cases-head h2', '.cx-case-card',
      '.cx-faqs-left h2', '.cx-faqs-left p', '.cx-faq',
      '.cx-cta-text h2', '.cx-cta-text p', '.cx-form-card',
      // Platforms page
      '.cx-plat-text h2', '.cx-plat-text > p', '.cx-plat-lead',
      '.cx-feat-item', '.cx-data-card',
      '.cx-services-heading', '.cx-services-body', '.cx-svc-row',
      '.cx-stat-item',
      // Security page
      '.cx-sec-intro h2', '.cx-sec-intro p', '.cx-sec-card',
      '.cx-sec-cta h2',
      // Case studies page
      '.cx-cs-item',
      // About page (new)
      '.cx-ap-text h2', '.cx-ap-text p',
      '.cx-ap-intro h2', '.cx-ap-intro p',
      '.cx-ap-plat', '.cx-ap-aud', '.cx-ap-why-item',
      '.cx-about-cta h2', '.cx-about-cta p',
      // Legacy about page
      '.about-section h2', '.about-section p',
      '.why-item', '.tech-item', '.stat-item',
      // Book demo
      '.booking-progress', '.form-step.active h2'
    ];

    autoTargets.forEach(function (sel) {
      document.querySelectorAll(sel).forEach(function (el) {
        if (!el.classList.contains('reveal')) {
          el.classList.add('reveal');
        }
      });
    });

    // Stagger photo wraps
    var photoWraps = document.querySelectorAll('.cx-about-photos');
    photoWraps.forEach(function (wrap) {
      wrap.classList.add('reveal-group');
      wrap.querySelectorAll('.cx-photo-wrap').forEach(function (p) {
        p.classList.add('reveal');
      });
    });

    // Stagger team cards
    var teamGrid = document.querySelector('.cx-team-grid');
    if (teamGrid) teamGrid.classList.add('reveal-group');

    // Stagger service rows
    var svcList = document.querySelector('.cx-service-list');
    if (svcList) svcList.classList.add('reveal-group');

    // Stagger stat items
    var statsRow = document.querySelector('.cx-stats-row');
    if (statsRow) statsRow.classList.add('reveal-group');

    // Stagger why-grid items
    var whyGrid = document.querySelector('.why-grid');
    if (whyGrid) whyGrid.classList.add('reveal-group');

    // Stagger tech items
    var techFeatures = document.querySelector('.tech-features');
    if (techFeatures) techFeatures.classList.add('reveal-group');

    // Stagger impact stats
    var impactStats = document.querySelector('.impact-stats');
    if (impactStats) impactStats.classList.add('reveal-group');

    // Stagger overview cards (homepage)
    var overviewGrid = document.querySelector('.cx-overview-grid');
    if (overviewGrid) overviewGrid.classList.add('reveal-group');

    // Stagger for-grid cards (homepage)
    var forGrid = document.querySelector('.cx-for-grid');
    if (forGrid) forGrid.classList.add('reveal-group');

    // Stagger case cards (homepage + case studies)
    var casesGrid = document.querySelector('.cx-cases-grid');
    if (casesGrid) casesGrid.classList.add('reveal-group');

    // Stagger security pillars (homepage)
    var secPillars = document.querySelector('.cx-sec-pillars');
    if (secPillars) secPillars.classList.add('reveal-group');

    // Stagger security cards (security page)
    var secCardGrid = document.querySelector('.cx-sec-grid');
    if (secCardGrid) secCardGrid.classList.add('reveal-group');

    // Stagger feat grids (platforms page)
    document.querySelectorAll('.cx-feat-grid').forEach(function (g) {
      g.classList.add('reveal-group');
    });

    // Stagger about page grids
    ['cx-ap-platforms', 'cx-ap-audience', 'cx-ap-why'].forEach(function (cls) {
      var el = document.querySelector('.' + cls);
      if (el) el.classList.add('reveal-group');
    });

    // Observer
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.12,
      rootMargin: '0px 0px -60px 0px'
    });

    document.querySelectorAll('.reveal').forEach(function (el) {
      observer.observe(el);
    });
  }


  /* ── 3. PARALLAX ───────────────────────────────────────────────
     Elements with class "parallax-section" get a subtle vertical
     shift on scroll — the classic WordPress depth effect.
     Speed is gentle (0.25) so it doesn't feel jarring.
  ──────────────────────────────────────────────────────────────── */
  function initParallax() {
    var sections = document.querySelectorAll('.parallax-section');
    if (!sections.length) return;

    var ticking = false;

    function updateParallax() {
      var scrollY = window.pageYOffset;
      sections.forEach(function (section) {
        var rect = section.getBoundingClientRect();
        var inView = rect.bottom > 0 && rect.top < window.innerHeight;
        if (!inView) return;
        var speed = parseFloat(section.dataset.parallaxSpeed) || 0.25;
        var offset = (scrollY - (scrollY + rect.top - window.innerHeight / 2)) * speed;
        var bg = section.querySelector('.parallax-bg');
        if (bg) {
          bg.style.transform = 'translateY(' + offset + 'px)';
        } else {
          // Subtle section shift
          section.style.backgroundPositionY = (offset * 0.5) + 'px';
        }
      });
      ticking = false;
    }

    window.addEventListener('scroll', function () {
      if (!ticking) {
        requestAnimationFrame(updateParallax);
        ticking = true;
      }
    }, { passive: true });

    updateParallax();
  }


  /* ── 5. SCROLL PROGRESS BAR ────────────────────────────────────
     Thin blue line at the very top of the viewport.
  ──────────────────────────────────────────────────────────────── */
  function initProgressBar() {
    var bar = document.createElement('div');
    bar.className = 'mn-progress-bar';
    document.body.appendChild(bar);

    window.addEventListener('scroll', function () {
      var scrolled = window.pageYOffset;
      var total = document.documentElement.scrollHeight - window.innerHeight;
      var pct = total > 0 ? (scrolled / total) * 100 : 0;
      bar.style.width = pct + '%';
    }, { passive: true });
  }


  /* ── 6. SMOOTH ANCHOR SCROLL ───────────────────────────────────
     Intercepts all #anchor links for smooth eased scrolling.
  ──────────────────────────────────────────────────────────────── */
  function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
      anchor.addEventListener('click', function (e) {
        var id = this.getAttribute('href').slice(1);
        if (!id) return;
        var target = document.getElementById(id);
        if (!target) return;
        e.preventDefault();
        var offset = 80; // header height
        var targetY = target.getBoundingClientRect().top + window.pageYOffset - offset;
        smoothScrollTo(targetY, 900);
      });
    });
  }

  function smoothScrollTo(targetY, duration) {
    var startY = window.pageYOffset;
    var diff = targetY - startY;
    var startTime = null;

    function easeInOutCubic(t) {
      return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
    }

    function step(timestamp) {
      if (!startTime) startTime = timestamp;
      var elapsed = timestamp - startTime;
      var progress = Math.min(elapsed / duration, 1);
      window.scrollTo(0, startY + diff * easeInOutCubic(progress));
      if (progress < 1) requestAnimationFrame(step);
    }

    requestAnimationFrame(step);
  }

})();
