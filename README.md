# Machineova - Advanced Voting Solutions Website

## Project Overview
Machineova is a modern, responsive website for innovative voting solutions with smooth PHP-like scrolling, WordPress lightness effects, and advanced animations.

## Setup Instructions

### 1. Logo Setup
- Place the Machinova logo image in the `assets/` folder
- Filename: `logo.png`
- Recommended size: 200x100px or larger
- The logo will automatically scale to fit the header

### 2. File Structure
```
machinova/
├── index.html           # Main HTML file
├── styles.css           # Main stylesheet
├── script.js            # JavaScript functionality
├── logo.svg             # SVG logo backup
├── assets/
│   └── logo.png         # PNG logo (place your image here)
├── OPTIMIZATION_GUIDE.md # Performance optimization details
└── README.md            # This file
```

### 3. Features

#### Mobile Responsive
- Fully responsive design for all screen sizes
- Breakpoints: 768px (tablet), 480px (mobile)
- Hamburger menu for mobile navigation
- Touch-friendly interactions

#### Smooth Scrolling & Animations
- PHP-like smooth scrolling with easing functions
- WordPress-style lightness effects
- Parallax effects on hero section
- Staggered animations on elements
- Smooth FAQ accordion with height animation

#### Performance Optimizations
- Lazy loading for images
- Passive event listeners
- RequestAnimationFrame throttling
- CSS will-change for GPU acceleration
- Prefetch strategy for internal links

#### Advanced Features
- Smooth header blur effect on scroll
- Active navigation highlighting
- Smooth form interactions
- Notification system
- Ripple effects on buttons
- Card hover animations

### 4. Browser Support
- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Mobile browsers (iOS Safari 14+, Chrome Android)

### 5. Customization

#### Colors
Edit the CSS variables in `styles.css`:
```css
:root {
  --blue: #0066FF;
  --blue-hover: #0052cc;
  --black: #000;
  --dark-gray: #1a1a1a;
  --border: #333;
  --text-gray: #999;
  --text-dark-gray: #666;
}
```

#### Typography
The website uses Google Fonts "Inter" with weights 100-900. All text elements automatically use this font.

#### Spacing & Layout
Modify the `.container` max-width and padding in `styles.css` to adjust layout.

### 6. Deployment

#### Local Testing
1. Open `index.html` in a modern web browser
2. Test on mobile devices using browser DevTools
3. Check performance using Lighthouse

#### Production Deployment
1. Ensure all assets are in the correct folders
2. Optimize images before deployment
3. Enable gzip compression on server
4. Set up caching headers
5. Monitor Core Web Vitals

### 7. Performance Tips

- Compress images to reduce file size
- Use CDN for static assets
- Enable browser caching
- Minify CSS and JavaScript for production
- Use lazy loading for below-the-fold images
- Monitor performance with Lighthouse

### 8. Troubleshooting

**Logo not showing:**
- Ensure `assets/logo.png` exists
- Check file path in HTML
- Verify image format is PNG

**Animations not smooth:**
- Check browser compatibility
- Disable browser extensions
- Clear browser cache
- Test in incognito mode

**Mobile menu not working:**
- Ensure JavaScript is enabled
- Check hamburger button visibility
- Test on actual mobile device

### 9. Support & Updates

For issues or feature requests, please refer to the GitHub repository:
https://github.com/X-culture24/machineova.git

### 10. License

This project is part of the Machineova voting solutions platform.

---

**Last Updated:** March 2026
**Version:** 2.0
**Status:** Production Ready
