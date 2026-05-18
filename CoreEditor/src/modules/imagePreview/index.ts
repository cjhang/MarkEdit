import { globalState } from '../../common/store';

let currentLinkElement: HTMLElement | null = null;
let showTimer: ReturnType<typeof setTimeout> | null = null;
let hideTimer: ReturnType<typeof setTimeout> | null = null;
let tooltip: HTMLElement | null = null;
let themeStyle: HTMLStyleElement | null = null;

export function setUpImagePreview(): void {
  document.addEventListener('mouseover', handleMouseOver, false);
  document.addEventListener('mouseout', handleMouseOut, false);
  applyThemeColors();
}

function resolveImageUrl(url: string): string {
  if (/^(https?:|data:)/i.test(url)) {
    return url;
  }
  return `image-loader://${url}`;
}

function getOrCreateTooltip(): HTMLElement {
  if (tooltip === null) {
    tooltip = document.createElement('div');
    tooltip.className = 'cm-md-imagePreview';
    tooltip.setAttribute('hidden', '');
    tooltip.innerHTML = `
      <div class="cm-md-imagePreview-loading"></div>
      <img class="cm-md-imagePreview-img" alt="">
      <div class="cm-md-imagePreview-error" hidden>Failed to load image</div>
    `;
    document.body.appendChild(tooltip);
  }
  return tooltip;
}

function handleMouseOver(event: MouseEvent): void {
  const target = event.target as HTMLElement;
  const linkElement = target.closest<HTMLElement>('.cm-md-link[data-link-is-image="true"]');
  if (!linkElement || linkElement === currentLinkElement) {
    return;
  }

  currentLinkElement = linkElement;

  if (hideTimer !== null) {
    clearTimeout(hideTimer);
    hideTimer = null;
  }

  if (showTimer === null) {
    showTimer = setTimeout(() => {
      showImagePreview(linkElement);
      showTimer = null;
    }, 300);
  }
}

function handleMouseOut(event: MouseEvent): void {
  const target = event.target as HTMLElement;
  const relatedTarget = event.relatedTarget as HTMLElement | null;

  const leavingLink = target.closest('.cm-md-link[data-link-is-image="true"]');
  const enteringTooltip = relatedTarget?.closest('.cm-md-imagePreview');
  const enteringLink = relatedTarget?.closest('.cm-md-link[data-link-is-image="true"]');
  const leavingTooltip = target.closest('.cm-md-imagePreview');

  // Cancel pending show if leaving the link before debounce fires
  if (leavingLink && showTimer !== null) {
    clearTimeout(showTimer);
    showTimer = null;
    currentLinkElement = null;
    return;
  }

  // Moving between tooltip and link, or within the same link: keep showing
  if ((leavingLink && (enteringTooltip || enteringLink)) || (leavingTooltip && enteringLink)) {
    return;
  }

  // Leaving the link or tooltip entirely
  if (leavingLink || leavingTooltip) {
    if (hideTimer === null) {
      hideTimer = setTimeout(() => {
        hideImagePreview();
        hideTimer = null;
      }, 200);
    }
  }
}

function showImagePreview(linkElement: HTMLElement): void {
  const url = linkElement.dataset.linkUrl;
  if (url === undefined || url === '') {
    return;
  }

  const imageUrl = resolveImageUrl(url);
  const tooltipEl = getOrCreateTooltip();

  const img = tooltipEl.querySelector('.cm-md-imagePreview-img') as HTMLImageElement;
  const loading = tooltipEl.querySelector('.cm-md-imagePreview-loading') as HTMLElement;
  const error = tooltipEl.querySelector('.cm-md-imagePreview-error') as HTMLElement;

  loading.removeAttribute('hidden');
  error.setAttribute('hidden', '');
  img.removeAttribute('hidden');
  img.src = '';

  img.onload = () => {
    loading.setAttribute('hidden', '');
  };

  img.onerror = () => {
    loading.setAttribute('hidden', '');
    img.setAttribute('hidden', '');
    error.removeAttribute('hidden');
  };

  img.src = imageUrl;

  positionTooltip(linkElement, tooltipEl);
  tooltipEl.removeAttribute('hidden');
  ensureScrollListener();
}

function hideImagePreview(): void {
  if (tooltip !== null) {
    tooltip.setAttribute('hidden', '');
    const img = tooltip.querySelector('.cm-md-imagePreview-img') as HTMLImageElement;
    img.src = '';
  }
  currentLinkElement = null;
}

function positionTooltip(linkElement: HTMLElement, tooltipEl: HTMLElement): void {
  const maxWidth = 400;
  const maxHeight = 300;
  const gap = 8;
  const margin = 16;

  const linkRect = linkElement.getBoundingClientRect();

  // Measure with unconstrained dimensions first to get natural size
  tooltipEl.style.maxWidth = `${maxWidth}px`;
  tooltipEl.style.maxHeight = `${maxHeight}px`;
  tooltipEl.style.left = '0';
  tooltipEl.style.top = '0';

  const tooltipWidth = Math.min(tooltipEl.offsetWidth || maxWidth, maxWidth);
  const tooltipHeight = Math.min(tooltipEl.offsetHeight || maxHeight, maxHeight);

  // Center below the link by default
  let left = linkRect.left + (linkRect.width - tooltipWidth) / 2;
  let top = linkRect.bottom + gap;

  // Flip above if not enough room below
  if (top + tooltipHeight > window.innerHeight - margin) {
    top = linkRect.top - tooltipHeight - gap;
  }

  // Clamp vertically
  if (top < margin) {
    top = linkRect.bottom + gap;
  }

  // Clamp horizontally
  left = Math.max(margin, Math.min(left, window.innerWidth - tooltipWidth - margin));
  top = Math.max(margin, Math.min(top, window.innerHeight - tooltipHeight - margin));

  tooltipEl.style.left = `${left}px`;
  tooltipEl.style.top = `${top}px`;
}

let scrollBound = false;

function ensureScrollListener(): void {
  if (scrollBound) {
    return;
  }

  window.editor.scrollDOM.addEventListener('scroll', () => {
    if (tooltip && !tooltip.hasAttribute('hidden')) {
      hideImagePreview();
    }
  }, { passive: true });

  scrollBound = true;
}

function applyThemeColors(): void {
  const colors = globalState.colors;
  if (!colors) {
    return;
  }

  if (themeStyle === null) {
    themeStyle = document.createElement('style');
    document.head.appendChild(themeStyle);
  }

  themeStyle.textContent = `
    .cm-md-imagePreview {
      --cm-ip-bg: ${colors.background};
      --cm-ip-border: ${colors.text}33;
      --cm-ip-accent: ${colors.accent};
      --cm-ip-muted: ${colors.comment};
    }
    @media (prefers-color-scheme: dark) {
      .cm-md-imagePreview {
        --cm-ip-border: ${colors.text}44;
      }
    }
  `;
}
