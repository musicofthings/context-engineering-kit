# API Documentation
_Auto-fetched: 2026-05-24T05:54:09Z_
_Source: /home/runner/work/context-engineering-kit/context-engineering-kit/config/api_sources.json_

---

## ANTHROPIC-CLAUDE-CODE

_Claude Code hooks, skills, slash commands, subagents_

Source: https://docs.anthropic.com/en/docs/claude-code/hooks


```
<!DOCTYPE html><html lang="en" class="__variable_ed9089 __variable_ea4744 dark" data-banner-state="visible" data-assistant-state="closed" data-page-mode="none" data-current-path="/"><head><meta charSet="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/><link rel="preload" href="/docs/_next/static/media/bb3ef058b751a6ad-s.p.woff2" as="font" crossorigin="" type="font/woff2"/><link rel="preload" href="/docs/_next/static/media/c4b700dcb2187787-s.p.woff2" as="font" crossorigin="" type="font/woff2"/><link rel="preload" href="/docs/_next/static/media/e4af272ccee01ff0-s.p.woff2" as="font" crossorigin="" type="font/woff2"/><link rel="preload" as="image" href="https://mintcdn.com/claude-code/c5r9_6tjPMzFdDDT/logo/light.svg?fit=max&amp;auto=format&amp;n=c5r9_6tjPMzFdDDT&amp;q=85&amp;s=78fd01ff4f4340295a4f66e2ea54903c"/><link rel="preload" as="image" href="https://mintcdn.com/claude-code/c5r9_6tjPMzFdDDT/logo/dark.svg?fit=max&amp;auto=format&amp;n=c5r9_6tjPMzFdDDT&amp;q=85&amp;s=1298a0c3b3a1da603b190d0de0e31712"/><link rel="stylesheet" href="/docs/_next/static/css/93ae04b3d6755082.css?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" data-precedence="next"/><link rel="stylesheet" href="/docs/_next/static/css/1accfb39600dfcdc.css?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" data-precedence="next"/><link rel="stylesheet" href="/docs/_next/static/css/05d6d8fcb903870d.css?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" data-precedence="next"/><link rel="preload" as="script" fetchPriority="low" href="/docs/_next/static/chunks/webpack-57a847a158a86dab.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8"/><script src="/docs/_next/static/chunks/87c73c54-09e1ba5c70e60a51.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/90018-a60d3a845ec58afc.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/main-app-76ddd9525ef90e67.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/891cff7f-38ce37d594f7da31.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/78238-22782f5aac7a6ef4.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/51288-0fb44d6be82e9af5.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/95115-7f3830b22524c9f1.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/14079-4865f1ab1b5bbf4b.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/31267-b6d776b25e075413.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/98816-4875194b6205382d.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/80239-ce217fc534a5bb94.js?dpl=dpl_4mSKfA8275Jom7xcMAN2g1PJ4SE8" async=""></script><script src="/docs/_next/static/chunks/1
```


---

## ANTHROPIC-API

_Claude API messages, models, pricing_

Source: https://docs.anthropic.com/en/api/getting-started


```
<!DOCTYPE html><html class="h-screen antialiased bg-bg-100 __variable_8d1da5 __variable_2d8cf6 __variable_5581e8" lang="en-US" data-theme="claude" data-mode="auto"><head><meta charSet="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover"/><link rel="stylesheet" href="/_next/static/css/3eeabce94b4f79c9.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/5bdd0eede93014d4.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/05674d3eb9977543.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/28ca58211539440e.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/f98c8674bf1a987b.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/4c1c1b178f5f2484.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/7330c74f27c4968a.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/bf71b0902a17bea2.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/5223b2ec25c12d41.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/e3aaf70fa4198b12.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/8359068e4bd1e0f6.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/838a5bb20f918e6c.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="stylesheet" href="/_next/static/css/ca19eb18ec0f21ea.css" nonce="R7BLj4qGkybv+U/8YtCfIA==" data-precedence="next"/><link rel="preload" as="script" fetchPriority="low" nonce="R7BL
```


---

## CLOUDFLARE-WORKERS

_Cloudflare Workers API for edge deployment_

Source: https://developers.cloudflare.com/workers/


```
<!DOCTYPE html><html lang="en" dir="ltr" data-theme="dark" data-has-toc data-has-sidebar class="astro-iqjk6a7v"> <head><script type="module" src="/_astro/Head.astro_astro_type_script_index_0_lang.DzFUDi6m.js"></script> <script type="module" src="/_astro/Head.astro_astro_type_script_index_1_lang.LFPxVEoI.js"></script> <script type="module" src="/_astro/Head.astro_astro_type_script_index_2_lang.DdMWwAGS.js"></script> <script type="module" src="/_astro/Head.astro_astro_type_script_index_3_lang.DibilYbp.js"></script> <script type="module" src="/_astro/Head.astro_astro_type_script_index_4_lang.TkaWOEUf.js"></script> <meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/><title>Overview · Cloudflare Workers docs</title><link rel="canonical" href="https://developers.cloudflare.com/workers/"/><link rel="sitemap" href="/sitemap-index.xml"/><link rel="shortcut icon" href="/favicon.png" type="image/png"/><meta name="generator" content="Astro v6.3.1"/><meta name="generator" content="Starlight v0.39.2"/><meta property="og:title" content="Cloudflare Workers"/><meta property="og:type" content="article"/><meta property="og:url" content="https://developers.cloudflare.com/workers/"/><meta property="og:locale" content="en"/><meta property="og:description" content="Build and deploy serverless applications across Cloudflare's global network with Workers."/><meta property="og:site_name" content="Cloudflare Docs"/><meta name="twitter:card" content="summary_large_image"/><meta name="description" content="Build and deploy serverless applications across Cloudflare's global network with Workers."/><meta name="twitter:site" content="@cloudflare"/><meta name="pcx_content_group" content="Developer platform"/><link rel="alternate" type="text/markdown" href="https://developers.cloudflare.com/workers/index.md"/><meta property="og:title" content="Overview · Cloudflare Workers docs"/><meta name="pcx_product" content="Workers"/><meta name="algolia_product_filter" content="Workers"/><meta name="pcx_content_type" content="Overview"/><meta name="algolia_content_type" content="Overview"/><meta name="pcx_additional_products" content="Workers"/><meta name="pcx_last_modified" content="30"/><meta property="image" content="https://developers.cloudflare.com/dev-products-preview.png"/><meta property="og:image" content="https://developers.cloudflare.com/dev-products-preview.png"/><meta property="twitter:image" content="https://developers.cloudflare.com/dev-products-preview.png"/><script>
	window.StarlightThemeProvider = (() => {
		const storedTheme =
			typeof localStorage !== 'undefined' && localStorage.getItem('starlight-theme');
		const theme =
			storedTheme ||
			(window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
		document.documentElement.dataset.theme = theme === 'light' ? 'light' : 'dark';
		return {
			updatePickers(theme = storedTheme || 'auto') {
				document.querySelectorAll('starlight-theme-select').forEach((picker
```


---
