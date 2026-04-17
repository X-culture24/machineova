// ========================================
// MACHINEOVA - MODERN WEBSITE SCRIPT
// ========================================

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', initializeWebsite);

function initializeWebsite() {
  // Force all visibility
  forceAllVisibility();
  
  // Initialize features
  initializeNavigation();
  initializeLazyAnimations();
  initializeFAQs();
  initializeFormInteractions();
  initializeScrollEffects();
  initializeIconVisibility();
}

// ========================================
// FORCE ALL VISIBILITY
// ========================================
function forceAllVisibility() {
  // Make all sections visible
  document.querySelectorAll('section').forEach(section => {
    section.style.opacity = '1';
    section.style.visibility = 'visible';
    section.style.display = 'block';
  });
  
  // Make all lazy text visible
  document.querySelectorAll('.lazy-text, .lazy-heading, .lazy-heading .word').forEach(el => {
    el.style.opacity = '1';
    el.style.visibility = 'visible';
  });
  
  // Make all icons visible
  document.querySelectorAll('i[class*="fa"]').forEach(icon => {
    icon.style.opacity = '1';
    icon.style.visibility = 'visible';
    icon.style.display = 'inline-block';
  });
  
  // Make body visible
  document.body.style.opacity = '1';
  document.body.style.visibility = 'visible';
}

// ========================================
// NAVIGATION
// ========================================
function initializeNavigation() {
  const hamburger = document.getElementById('hamburger');
  const navMenu = document.getElementById('navMenu');
  
  if (hamburger) {
    hamburger.addEventListener('click', () => {
      navMenu.classList.toggle('active');
      hamburger.classList.toggle('active');
      document.body.style.overflow = navMenu.classList.contains('active') ? 'hidden' : 'auto';
    });
  }
  
  // Close menu on link click
  document.querySelectorAll('.nav-menu a').forEach(link => {
    link.addEventListener('click', () => {
      if (navMenu) {
        navMenu.classList.remove('active');
        if (hamburger) hamburger.classList.remove('active');
        document.body.style.overflow = 'auto';
      }
    });
  });
  
  // Smooth anchor scrolling
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      e.preventDefault();
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });
}

// ========================================
// LAZY ANIMATIONS
// ========================================
function initializeLazyAnimations() {
  // Lazy text observer
  const lazyTextObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        entry.target.style.opacity = '1';
        entry.target.style.visibility = 'visible';
        lazyTextObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });
  
  // Observe all lazy text elements
  document.querySelectorAll('.lazy-text, .lazy-heading, .section-header p, .feature-card h3, .standout-card h3, .security-card h3, .problem-card h3, .about-text p, .vision-list li, .commitment-list li, .feature-highlights li, .why-item h3, .why-item p, .tech-item h4, .tech-item p, .problem-desc, .stat-number, .testimonial-card p, .faq-question span, .pricing-highlight, .footer-col h4').forEach(el => {
    el.classList.add('visible');
    el.style.opacity = '1';
    el.style.visibility = 'visible';
    lazyTextObserver.observe(el);
  });
  
  // Lazy heading word animation
  document.querySelectorAll('.lazy-heading').forEach(heading => {
    const words = heading.querySelectorAll('.word');
    words.forEach((word, index) => {
      word.style.animationDelay = `${0.1 + (index * 0.1)}s`;
      word.style.opacity = '1';
      word.style.visibility = 'visible';
    });
  });
  
  // Card animation observer
  const cardObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry, index) => {
      if (entry.isIntersecting) {
        setTimeout(() => {
          entry.target.style.opacity = '1';
          entry.target.style.transform = 'translateY(0)';
          entry.target.style.visibility = 'visible';
        }, index * 50);
        cardObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1 });
  
  document.querySelectorAll('.feature-card, .standout-card, .security-card, .testimonial-card, .problem-card, .why-item, .tech-item').forEach(card => {
    card.style.opacity = '0';
    card.style.transform = 'translateY(20px)';
    card.style.transition = 'all 0.6s cubic-bezier(0.25, 0.46, 0.45, 0.94)';
    card.style.visibility = 'visible';
    cardObserver.observe(card);
  });
}

// ========================================
// FAQs - ENHANCED DROPDOWN
// ========================================
function initializeFAQs() {
  document.querySelectorAll('.faq-question').forEach(question => {
    question.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      
      const faqItem = this.closest('.faq-item');
      if (!faqItem) return;
      
      const isActive = faqItem.classList.contains('active');
      const answer = faqItem.querySelector('.faq-answer');
      if (!answer) return;
      
      // Close other items with smooth animation
      document.querySelectorAll('.faq-item.active').forEach(item => {
        if (item !== faqItem) {
          item.classList.remove('active');
          const ans = item.querySelector('.faq-answer');
          if (ans) {
            ans.style.maxHeight = '0px';
            ans.style.opacity = '0';
            ans.style.padding = '0 1.5rem';
          }
        }
      });
      
      // Toggle current item with smooth animation
      if (!isActive) {
        faqItem.classList.add('active');
        // Calculate height dynamically
        answer.style.display = 'block';
        const scrollHeight = answer.scrollHeight;
        answer.style.maxHeight = scrollHeight + 'px';
        answer.style.opacity = '1';
        answer.style.padding = '0 1.5rem 1.5rem 1.5rem';
        
        // Recalculate on window resize
        const resizeHandler = () => {
          if (faqItem.classList.contains('active')) {
            answer.style.maxHeight = answer.scrollHeight + 'px';
          }
        };
        window.addEventListener('resize', resizeHandler);
      } else {
        faqItem.classList.remove('active');
        answer.style.maxHeight = '0px';
        answer.style.opacity = '0';
        answer.style.padding = '0 1.5rem';
      }
    });
  });
}

// ========================================
// FORM INTERACTIONS
// ========================================
function initializeFormInteractions() {
  document.querySelectorAll('.form-group input, .form-group textarea, input[type="text"], input[type="email"], textarea').forEach(input => {
    input.addEventListener('focus', function() {
      this.style.borderColor = 'var(--blue)';
      this.style.boxShadow = '0 0 0 3px rgba(0, 102, 255, 0.1)';
      this.style.transition = 'all 0.3s ease';
    });
    
    input.addEventListener('blur', function() {
      this.style.borderColor = 'var(--border)';
      this.style.boxShadow = 'none';
    });
  });
}

// ========================================
// SCROLL EFFECTS
// ========================================
function initializeScrollEffects() {
  let lastScroll = 0;
  const header = document.querySelector('.header');
  
  window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;
    const scrollDelta = Math.abs(currentScroll - lastScroll);
    
    if (scrollDelta > 5 && header) {
      if (currentScroll > 100) {
        header.style.background = 'rgba(0, 0, 0, 0.98)';
        header.style.backdropFilter = 'blur(12px)';
        header.style.boxShadow = '0 8px 32px rgba(0, 102, 255, 0.15)';
      } else {
        header.style.background = '#000';
        header.style.boxShadow = 'none';
      }
    }
    
    lastScroll = currentScroll;
  }, { passive: true });
  
  // Parallax effect on hero
  window.addEventListener('scroll', () => {
    const scrolled = window.pageYOffset;
    const heroBox = document.querySelector('.hero-box');
    
    if (heroBox && scrolled < 800) {
      const parallaxValue = scrolled * 0.08;
      heroBox.style.transform = `translateY(${parallaxValue}px)`;
      heroBox.style.opacity = Math.max(0.5, 1 - (scrolled / 1000));
    }
  }, { passive: true });
}

// ========================================
// ICON VISIBILITY
// ========================================
function initializeIconVisibility() {
  // Ensure all Font Awesome icons are visible
  document.querySelectorAll('i[class*="fa"]').forEach(icon => {
    icon.style.opacity = '1';
    icon.style.visibility = 'visible';
    icon.style.display = 'inline-block';
    icon.style.color = 'inherit';
  });
  
  // Social media icons
  document.querySelectorAll('.social-icons a i').forEach(icon => {
    icon.style.color = '#fff';
    icon.style.fontSize = '1rem';
    icon.style.display = 'block';
    icon.style.lineHeight = '1';
  });
  
  // Feature icons
  document.querySelectorAll('.standout-icon, .why-icon, .stat-icon').forEach(icon => {
    icon.style.opacity = '1';
    icon.style.visibility = 'visible';
    icon.style.display = 'flex';
  });
}

// ========================================
// BUTTON INTERACTIONS
// ========================================
document.querySelectorAll('.btn, .cta-btn').forEach(btn => {
  btn.addEventListener('mouseenter', function() {
    this.style.transform = 'translateY(-3px)';
    this.style.boxShadow = '0 8px 24px rgba(0, 102, 255, 0.4)';
  });
  
  btn.addEventListener('mouseleave', function() {
    this.style.transform = 'translateY(0)';
    this.style.boxShadow = '';
  });
});

// ========================================
// CARD HOVER EFFECTS
// ========================================
document.querySelectorAll('.feature-card, .testimonial-card, .standout-item').forEach(card => {
  card.addEventListener('mouseenter', function() {
    this.style.transform = 'translateY(-8px) scale(1.02)';
    this.style.boxShadow = '0 20px 50px rgba(0, 102, 255, 0.25)';
    this.style.transition = 'all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)';
  });
  
  card.addEventListener('mouseleave', function() {
    this.style.transform = 'translateY(0) scale(1)';
    this.style.boxShadow = '';
    this.style.transition = 'all 0.3s ease';
  });
});

// ========================================
// NOTIFICATION SYSTEM
// ========================================
function showNotification(message) {
  const notification = document.createElement('div');
  notification.textContent = message;
  notification.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: linear-gradient(135deg, #0066FF, #0052cc);
    color: #fff;
    padding: 16px 24px;
    border-radius: 12px;
    font-family: 'Inter', sans-serif;
    font-weight: 600;
    z-index: 10000;
    box-shadow: 0 8px 24px rgba(0, 102, 255, 0.4);
    animation: slideInRight 0.4s ease;
    backdrop-filter: blur(10px);
  `;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.style.animation = 'slideOutRight 0.4s ease';
    setTimeout(() => notification.remove(), 400);
  }, 3000);
}

// Add animation keyframes
const style = document.createElement('style');
style.textContent = `
  @keyframes slideInRight {
    from { opacity: 0; transform: translateX(100px); }
    to { opacity: 1; transform: translateX(0); }
  }
  @keyframes slideOutRight {
    from { opacity: 1; transform: translateX(0); }
    to { opacity: 0; transform: translateX(100px); }
  }
  @keyframes fadeInUp {
    from { opacity: 0; transform: translateY(20px); }
    to { opacity: 1; transform: translateY(0); }
  }
  @keyframes slideUp {
    from { opacity: 0; transform: translateY(30px); }
    to { opacity: 1; transform: translateY(0); }
  }
`;
document.head.appendChild(style);

// Export for use in other scripts
window.showNotification = showNotification;
