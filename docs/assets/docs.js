/* ============================================================
   VACE Docs — bundled JS
   Self-contained. No dependencies. Works from file://.
   ============================================================ */

(function () {
  'use strict';

  // ---------- Sidebar toggle (mobile) ----------
  const sidebar  = document.getElementById('docSidebar');
  const toggle   = document.getElementById('docToggle');
  const backdrop = document.getElementById('docBackdrop');

  if (toggle && sidebar && backdrop) {
    const open  = () => {
      sidebar.classList.add('is-open');
      backdrop.classList.add('is-open');
      document.body.style.overflow = 'hidden';
    };
    const close = () => {
      sidebar.classList.remove('is-open');
      backdrop.classList.remove('is-open');
      document.body.style.overflow = '';
    };
    toggle.addEventListener('click', () => {
      sidebar.classList.contains('is-open') ? close() : open();
    });
    backdrop.addEventListener('click', close);
    sidebar.querySelectorAll('a').forEach(a => a.addEventListener('click', close));
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && sidebar.classList.contains('is-open')) close();
    });
  }

  // ---------- Build "On this page" TOC ----------
  const tocList = document.getElementById('docTocList');
  const content = document.getElementById('docContent');

  if (tocList && content) {
    const headings = content.querySelectorAll('h2[id], h3[id]');

    headings.forEach(h => {
      const a = document.createElement('a');
      a.href = '#' + h.id;
      a.textContent = h.textContent.replace(/\s*#\s*$/, '');
      if (h.tagName === 'H3') a.classList.add('toc-h3');
      tocList.appendChild(a);
    });

    const links = tocList.querySelectorAll('a');

    if (links.length === 0) {
      const toc = document.getElementById('docToc');
      if (toc) toc.style.display = 'none';
    } else {
      const spy = new IntersectionObserver(entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            links.forEach(l => l.classList.remove('is-active'));
            const active = tocList.querySelector(`a[href="#${entry.target.id}"]`);
            if (active) active.classList.add('is-active');
          }
        });
      }, { rootMargin: '-30% 0px -60% 0px', threshold: 0 });

      headings.forEach(h => spy.observe(h));
    }
  }

  // ---------- Copy buttons on every code block ----------
  document.querySelectorAll('.doc-code').forEach(block => {
    const copyBtn = block.querySelector('.doc-code__copy');
    const code    = block.querySelector('pre code');
    if (!copyBtn || !code) return;

    copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.innerText);
        const original = copyBtn.textContent;
        copyBtn.textContent = 'Copied';
        copyBtn.classList.add('is-copied');
        setTimeout(() => {
          copyBtn.textContent = original;
          copyBtn.classList.remove('is-copied');
        }, 1400);
      } catch {
        copyBtn.textContent = 'Press Ctrl+C';
        setTimeout(() => { copyBtn.textContent = 'Copy'; }, 1400);
      }
    });
  });

  // ---------- Smooth scroll for same-page anchors ----------
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
      const id = a.getAttribute('href').slice(1);
      if (!id) return;
      const target = document.getElementById(id);
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      history.replaceState(null, '', '#' + id);
    });
  });

  // ---------- Back to top ----------
  const toTop = document.getElementById('docTop');
  if (toTop) {
    window.addEventListener('scroll', () => {
      toTop.classList.toggle('show', window.scrollY > 400);
    });
    toTop.addEventListener('click', () => {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  // ---------- Keyboard: "/" to focus search ----------
  const search = document.querySelector('.doc-header__search input');
  if (search) {
    document.addEventListener('keydown', e => {
      if (e.key === '/' &&
          document.activeElement !== search &&
          !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
        e.preventDefault();
        search.focus();
      }
    });
  }
})();