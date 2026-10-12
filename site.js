/* ================================================================
   MACHINENOVA — SITE SCRIPT
   Replaces script.js, script-modern.js, machinenova.js and effects.js.
   All scroll work is batched into one passive, rAF-throttled listener.
   Anchor scrolling is native (CSS scroll-behavior + scroll-padding).
   ================================================================ */
(function () {
  'use strict';

  var root = document.documentElement;
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var hasIO = 'IntersectionObserver' in window;

  /* ── Toast (also used by booking.js) ─────────────────────────── */
  window.showNotification = function (message) {
    var old = document.querySelector('.mn-toast');
    if (old) old.remove();
    var t = document.createElement('div');
    t.className = 'mn-toast';
    t.setAttribute('role', 'status');
    t.textContent = message;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 3800);
  };

  /* ── Navigation ──────────────────────────────────────────────── */
  function initNav() {
    var hamburger = document.getElementById('hamburger');
    var menu = document.getElementById('navMenu');
    if (!hamburger || !menu) return;

    hamburger.setAttribute('aria-label', 'Toggle menu');
    hamburger.setAttribute('aria-expanded', 'false');

    function setOpen(open) {
      menu.classList.toggle('active', open);
      hamburger.classList.toggle('active', open);
      hamburger.setAttribute('aria-expanded', String(open));
      root.classList.toggle('nav-open', open);
    }

    hamburger.addEventListener('click', function () {
      setOpen(!menu.classList.contains('active'));
    });

    menu.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function (e) {
        var dd = link.closest('.nav-dropdown');
        if (dd && link.classList.contains('dropdown-trigger') && window.innerWidth <= 768) {
          e.preventDefault();
          dd.classList.toggle('open');
          return;
        }
        setOpen(false);
      });
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') setOpen(false);
    });
  }

  /* ── Scroll: header state + progress bar (one listener) ──────── */
  function initScroll() {
    var header = document.querySelector('.header');
    var bar = document.createElement('div');
    bar.className = 'mn-progress-bar';
    bar.setAttribute('aria-hidden', 'true');
    document.body.appendChild(bar);

    var ticking = false;
    var maxScroll = 1;

    var subnav = document.querySelector('.cx-plat-nav');
    function measure() {
      maxScroll = Math.max(1, root.scrollHeight - window.innerHeight);
      // keep sticky offsets and anchor landing in sync with the real header height
      if (header) root.style.setProperty('--header-h', header.offsetHeight + 'px');
      if (subnav) root.style.setProperty('--subnav-h', subnav.offsetHeight + 'px');
    }

    function update() {
      var y = window.pageYOffset || root.scrollTop;
      if (header) header.classList.toggle('is-scrolled', y > 24);
      bar.style.transform = 'scaleX(' + Math.min(1, y / maxScroll) + ')';
      ticking = false;
    }

    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }, { passive: true });

    window.addEventListener('resize', function () { measure(); update(); }, { passive: true });
    window.addEventListener('load', function () { measure(); update(); });
    measure();
    update();
  }

  /* ── Reveal on scroll ────────────────────────────────────────── */
  var REVEAL = [
    '.cx-trust-strip', '.cx-overview-head h2', '.cx-overview-head p', '.cx-ov-card',
    '.cx-about-heading', '.cx-about-body', '.cx-photo-wrap', '.cx-for-head h2', '.cx-for-card',
    '.cx-spotlight-text', '.cx-cmd-card', '.cx-sec-text', '.cx-sec-pillar',
    '.cx-cases-head', '.cx-case-card', '.cx-faqs-left', '.cx-faq', '.cx-cta-text', '.cx-form-card',
    '.cx-plat-text h2', '.cx-plat-text > p', '.cx-feat-item', '.cx-data-card',
    '.cx-sec-intro', '.cx-sec-card', '.cx-cs-item', '.cx-ap-text', '.cx-ap-intro', '.cx-ap-plat',
    '.cx-ap-aud', '.cx-ap-why-item', '.cx-about-cta h2', '.cx-about-cta p',
    '.mn-head', '.mn-card', '.mn-stat', '.shot', '.phone-row figure', '.mn-steps li',
    '.mn-table-wrap', '.mn-callout', '.mn-tabs', '.booking-progress'
  ];

  function initReveal() {
    if (!hasIO || reduceMotion) return;
    root.classList.add('js-reveal');

    // include elements tagged .reveal directly in the markup
    var els = document.querySelectorAll(REVEAL.join(',') + ', .reveal');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        // stagger siblings that enter together
        var idx = Array.prototype.indexOf.call(el.parentNode.children, el);
        el.style.transitionDelay = Math.min(idx, 5) * 70 + 'ms';
        el.classList.add('is-visible');
        io.unobserve(el);
      });
    }, { threshold: 0.08, rootMargin: '0px 0px -40px 0px' });

    els.forEach(function (el) {
      // Anything already on screen (e.g. after a #hash jump) shows immediately
      var r = el.getBoundingClientRect();
      el.classList.add('reveal');
      if (r.top < window.innerHeight && r.bottom > 0) {
        el.classList.add('is-visible');
      } else {
        io.observe(el);
      }
    });

    // Hero text: lazy-text fades in
    document.querySelectorAll('.lazy-text').forEach(function (el) { el.classList.add('visible'); });
  }

  /* ── Lazy images: fade in once decoded ───────────────────────── */
  function initLazyImages() {
    root.classList.add('js-lazy');
    document.querySelectorAll('img[loading="lazy"]').forEach(function (img) {
      function done() { img.classList.add('is-loaded'); }
      if (img.complete && img.naturalWidth) done();
      else {
        img.addEventListener('load', done, { once: true });
        img.addEventListener('error', done, { once: true });
      }
    });
  }

  /* ── Bars animate when their card scrolls in ─────────────────── */
  function initBars() {
    if (!hasIO || reduceMotion) return;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.querySelectorAll('.cx-bar-fill, .cx-cmd-fill').forEach(function (bar) {
          var w = bar.style.width;
          bar.style.transition = 'none';
          bar.style.width = '0';
          requestAnimationFrame(function () {
            requestAnimationFrame(function () {
              bar.style.transition = 'width 1.1s cubic-bezier(0.22,1,0.36,1)';
              bar.style.width = w;
            });
          });
        });
        io.unobserve(entry.target);
      });
    }, { threshold: 0.3 });
    document.querySelectorAll('.cx-data-card, .cx-cmd-card').forEach(function (c) { io.observe(c); });
  }

  /* ── FAQ accordion ───────────────────────────────────────────── */
  function initFaq() {
    document.querySelectorAll('.cx-faq-q').forEach(function (btn) {
      var item = btn.closest('.cx-faq');
      var panel = item && item.querySelector('.cx-faq-a');
      btn.setAttribute('aria-expanded', 'false');
      btn.addEventListener('click', function () {
        var open = !item.classList.contains('open');
        document.querySelectorAll('.cx-faq.open').forEach(function (other) {
          if (other === item) return;
          other.classList.remove('open');
          other.querySelector('.cx-faq-q').setAttribute('aria-expanded', 'false');
          var p = other.querySelector('.cx-faq-a');
          if (p) p.style.maxHeight = '';
        });
        item.classList.toggle('open', open);
        btn.setAttribute('aria-expanded', String(open));
        if (panel) panel.style.maxHeight = open ? panel.scrollHeight + 24 + 'px' : '';
      });
    });
  }

  /* ── Tabs (screenshot galleries) ─────────────────────────────── */
  function initTabs() {
    document.querySelectorAll('[data-tabs]').forEach(function (group) {
      var tabs = group.querySelectorAll('[role="tab"]');
      function select(tab, focus) {
        tabs.forEach(function (t) {
          var on = t === tab;
          t.setAttribute('aria-selected', String(on));
          t.tabIndex = on ? 0 : -1;
          var panel = document.getElementById(t.getAttribute('aria-controls'));
          if (!panel) return;
          panel.hidden = !on;
          if (on) {
            panel.classList.remove('is-entering');
            void panel.offsetWidth;
            panel.classList.add('is-entering');
            // panels hidden at load were never observed — show their reveal content now
            panel.querySelectorAll('.reveal').forEach(function (el) { el.classList.add('is-visible'); });
          }
        });
        if (focus) tab.focus();
      }
      tabs.forEach(function (tab, i) {
        tab.addEventListener('click', function () { select(tab); });
        tab.addEventListener('keydown', function (e) {
          var n = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
          if (!n) return;
          e.preventDefault();
          select(tabs[(i + n + tabs.length) % tabs.length], true);
        });
      });
    });
  }

  /* ── Lightbox for screenshots ────────────────────────────────── */
  function initLightbox() {
    var links = document.querySelectorAll('a.shot, a.phone-shot');
    if (!links.length || typeof HTMLDialogElement !== 'function') return;

    var dlg = document.createElement('dialog');
    dlg.className = 'mn-lightbox';
    dlg.innerHTML = '<button type="button" aria-label="Close"><i class="fa-solid fa-xmark"></i></button><img alt=""><p></p>';
    document.body.appendChild(dlg);
    var img = dlg.querySelector('img');
    var cap = dlg.querySelector('p');

    dlg.querySelector('button').addEventListener('click', function () { dlg.close(); });
    dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
    dlg.addEventListener('close', function () { img.removeAttribute('src'); });

    links.forEach(function (a) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var thumb = a.querySelector('img');
        img.src = a.getAttribute('href');
        img.alt = thumb ? thumb.alt : '';
        cap.textContent = a.dataset.caption || (thumb ? thumb.alt : '');
        dlg.showModal();
      });
    });
  }

  /* ── Platform sub-nav: highlight the section in view ─────────── */
  function initSubnav() {
    var nav = document.querySelector('.cx-plat-nav');
    if (!nav || !hasIO) return;
    var links = {};
    nav.querySelectorAll('a[href^="#"]').forEach(function (a) { links[a.getAttribute('href').slice(1)] = a; });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        Object.keys(links).forEach(function (id) { links[id].classList.toggle('is-active', id === entry.target.id); });
        var active = links[entry.target.id];
        if (active && active.scrollIntoView && nav.scrollWidth > nav.clientWidth) {
          active.parentNode.scrollTo({ left: active.offsetLeft - 16, behavior: reduceMotion ? 'auto' : 'smooth' });
        }
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    Object.keys(links).forEach(function (id) {
      var sec = document.getElementById(id);
      if (sec) io.observe(sec);
    });
  }

  /* ── Home contact form: open the visitor's email app ─────────── */
  function initHomeForm() {
    var form = document.getElementById('cx-home-form');
    if (!form) return;
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var f = form.elements;
      var lines = [
        'Name: ' + (f.name ? f.name.value : ''),
        'Email: ' + (f.email ? f.email.value : ''),
        'Organisation: ' + (f.organisation ? f.organisation.value : ''),
        'Platform of interest: ' + (f.platform ? f.platform.value : ''),
        '',
        f.message ? f.message.value : ''
      ];
      var href = 'mailto:sawe@machinenova.com?subject=' + encodeURIComponent('Demo request — MachineNova') +
        '&body=' + encodeURIComponent(lines.join('\n'));
      window.location.href = href;
      window.showNotification('Opening your email app to send the request…');
    });
  }

  /* ── Deep links: land exactly on #target, then enable smooth scroll ── */
  function initHashLanding() {
    function align() {
      var id = decodeURIComponent(location.hash.slice(1));
      var el = id && document.getElementById(id);
      if (el) el.scrollIntoView({ block: 'start', behavior: 'instant' in document.documentElement.style ? 'instant' : 'auto' });
    }
    function settle() {
      align();
      // re-align once web fonts have swapped in, then turn on smooth in-page scrolling
      var fonts = document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();
      fonts.then(function () {
        requestAnimationFrame(function () {
          align();
          if (!reduceMotion) root.classList.add('smooth-scroll');
        });
      });
    }
    if (document.readyState === 'complete') settle();
    else window.addEventListener('load', settle, { once: true });
  }

  function init() {
    initNav();
    initScroll();
    initReveal();
    initLazyImages();
    initBars();
    initFaq();
    initTabs();
    initLightbox();
    initSubnav();
    initHomeForm();
    if (location.hash) initHashLanding();
    else window.addEventListener('load', function () { if (!reduceMotion) root.classList.add('smooth-scroll'); }, { once: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
