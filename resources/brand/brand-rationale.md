# Cascade Identity & Logo Rationale

## Brand Job
Cascade is a native macOS window management engine. The mark must instantly convey three ideas to power users and engineers:
1. **Mathematical Invariant:** Staggered window geometry that never collides or completely occludes underlying windows.
2. **Permanent Clickability:** The signature unoccluded click tabs that remain exposed regardless of how many windows are open.
3. **Engineering Restraint:** A precision-crafted, native macOS tool adhering to the highest standards of Apple design and Swiss typography.

## Visual Idea
The visual mark directly renders the mathematical formula of Cascade:
$$X_i = (i-1)\delta, \quad Y_i = (i-1)\delta$$
Three stacked planar window frames progress diagonally across the canvas. Each underlying frame exposes its top-right tab ($P_i$), rendered as a distinct unoccluded geometric click zone. 

Unlike literal, noisy skeuomorphic designs (heavy drop shadows, simulated text, traffic lights), this minimalist mark relies on:
- Golden-ratio planar proportions ($1.45 : 1$).
- Negative-space separation channels for monochrome and small scales.
- Electric Cyan accent accents (`#38BDF8`) that signal active, responsive interaction.

## System
- **`brand-primary.svg`**: The master full-color app icon built on the macOS Big Sur squircle grid ($824 \times 824$ active container within $1024 \times 1024$).
- **`brand-mono.svg`**: Single-color vector utilizing `currentColor` and negative space knockouts. Survives 1-bit printing, embossing, laser engraving, and terminal CLI graphics.
- **`brand-inverse.svg`**: High-contrast variant tailored for dark interfaces and OLED displays.
- **`brand-small.svg`**: Simplified 2-plane optical silhouette calibrated for 16px to 64px (favicons, browser tabs, and application switchers).
- **`brand-animated.svg`**: Semantic CSS keyframe cascade illustrating the smooth window layout and tab illumination with strict `prefers-reduced-motion` compliance.
- **`brand-preview.html`**: Interactive design testbench displaying all scales and dark/light comparisons.

## Why This Should Work
1. **Recognition:** The diagonal progression of unoccluded tabs is unique in the window management space (unlike Rectangle's divided squares, Amethyst's tiles, or Magnet's halves).
2. **Small-Size Utility:** The small variant eliminates microscopic noise, keeping the tab and staggered edge crisp even at 16x16 pixels.
3. **Native macOS Fit:** The primary icon integrates seamlessly alongside standard macOS apps in the Dock, Launchpad, and System Settings.

## Risks & Mitigations
- **Trademark:** Cascade is an open-source MIT developer utility. A preliminary search reveals standard generic uses of "cascade" across software, but the proprietary combination with macOS window management geometry is unique.
- **Usage Boundaries:** Do not alter the relative aspect ratio of the window planes. When scaling below 32px, always switch to `brand-small.svg` or `brand-mono.svg`.
