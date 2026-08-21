# Cedros Digital

App do Clube de Desbravadores Cedros do Líbano — PWA (Progressive Web App).

Publicado em: https://cedros-digital.adrodrigues-ahi.workers.dev

## Como publicar

Hospedado no **Cloudflare Workers** (Workers & Pages → "Connect to Git"), com deploy automático a cada `git push` na branch `main` — configurado via [wrangler.toml](wrangler.toml) (site estático, sem build, servido a partir da raiz do repositório).

Pra publicar do zero:
1. No painel da Cloudflare, vá em **Workers & Pages → Create → Connect to Git** e selecione este repositório.
2. Build command: nenhum. Deploy command: `npx wrangler deploy` (usa o `wrangler.toml` já no repo).
3. Depois do primeiro deploy, em **Domains**, ative o toggle da URL `*.workers.dev` (vem desativado por padrão).

## Como atualizar depois

É só dar `git push` no repositório (branch `main`) — a Cloudflare detecta o commit e publica a nova versão automaticamente.

## Backend (Supabase)

Login, cadastro e o painel de Administração usam o Supabase (Postgres + Auth) — ver [supabase/schema.sql](supabase/schema.sql) para o schema (tabelas, função de permissões padrão e RLS).

## Gerar APK

Depois de publicado, use https://www.pwabuilder.com/ com a URL do site publicado para gerar o APK Android.
