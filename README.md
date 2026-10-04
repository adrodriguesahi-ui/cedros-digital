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

## Dar acesso a quem não tem e-mail

O login é o do Supabase Auth: a pessoa entra com e-mail e senha. Quem tem
e-mail de verdade pode se cadastrar sozinha e usar "esqueci a senha".

Boa parte do clube, porém, entrou pela planilha da Secretaria com e-mail de
fachada (`292536@sememail.local`). Esses endereços não recebem nada — nem
convite, nem link de recuperação. Pra essas pessoas, **o administrador define a
senha** em Administração → editar o usuário → *Senha de acesso*.

### Por que isso precisa de uma função no servidor

Definir a senha de outra pessoa exige a chave `service_role` do Supabase, que
ignora todas as regras de acesso do banco. O app é um HTML servido
publicamente: qualquer um lê o código-fonte. Se a chave estivesse lá, estaria
entregue — e com ela o banco inteiro, inclusive os dados dos menores.

Por isso a chave vive numa Edge Function (`supabase/functions/definir-acesso`),
onde o navegador nunca a vê. A função confere que **quem chamou é
administrador** lendo o token da sessão, não acreditando no que o app diz.

### Publicar a função (uma vez só)

Pelo painel: **Edge Functions → Deploy a new function**, nome `definir-acesso`,
e cole o conteúdo de `supabase/functions/definir-acesso/index.ts`.

Ou pelo terminal, com a [CLI do Supabase](https://supabase.com/docs/guides/cli):

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase functions deploy definir-acesso
```

As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY`
já são preenchidas pelo próprio Supabase — **não precisa cadastrar nada**, e a
`service_role` não deve ser copiada pra lugar nenhum.

Enquanto a função não estiver publicada, o botão avisa isso em vez de falhar
em silêncio.

### Na prática

1. Cadastre a pessoa normalmente (nome, e-mail, papel, unidade) e **salve**.
2. Reabra o cadastro, digite uma senha de pelo menos 8 caracteres e toque em
   **Definir**.
3. Passe e-mail e senha pra ela. Peça que troque depois, em Administração →
   Minha conta.

Salvar o usuário **nunca** mexe na senha — só o botão "Definir" faz isso.

## Instalar no celular

### Pelo navegador (sem aviso nenhum)

É o caminho mais simples, e serve pra maioria das pessoas do clube. Abra o site
publicado no Chrome do celular e use **⋮ → Adicionar à tela inicial**. Fica com
ícone próprio, abre em tela cheia e atualiza sozinho — não precisa reinstalar
nada, nunca.

O app instalado (APK) carrega **esse mesmo site** (ver `server.url` em
`capacitor.config.json`), então a diferença é pequena: o APK dá acesso a
recursos nativos (bandeja de compartilhar do PDF, vibração, cor da barra de
status) e o atalho do navegador não.

### Pelo APK — e o aviso de "app não seguro"

Todo APK instalado fora da Play Store faz o Android avisar que a fonte é
desconhecida. Isso não dá pra evitar sem publicar na loja.

O que **dá** pra evitar é o aviso mais feio, o de "app não seguro" do Play
Protect: ele aparece principalmente em build de **depuração**, que o Android
marca como depurável. Por isso o build pode ser assinado com uma chave própria
e sair como **release**.

#### Ligar a assinatura (uma vez só)

O workflow compila release assinado **se** existir o segredo
`ANDROID_KEYSTORE_BASE64`. Sem ele, continua compilando em debug, pra quem
clonar o repositório não precisar de chave nenhuma.

**1. Crie a chave** (num computador com Java; vale `keytool` do Android Studio):

```bash
keytool -genkeypair -v \
  -keystore cedros.keystore \
  -alias cedros \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass SUA_SENHA -keypass SUA_SENHA \
  -dname "CN=Clube de Desbravadores Cedros do Líbano, O=Cedros Digital, C=BR"
```

**2. Converta pra base64**, que é como o segredo guarda arquivo:

```bash
base64 -w0 cedros.keystore > cedros.keystore.b64
```

**3. Em Settings → Secrets and variables → Actions**, crie quatro segredos:

| Segredo | Valor |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | o conteúdo de `cedros.keystore.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | a senha que você escolheu |
| `ANDROID_KEY_ALIAS` | `cedros` |
| `ANDROID_KEY_PASSWORD` | a mesma senha |

**4. Guarde `cedros.keystore` e a senha fora do repositório** — num gerenciador
de senhas, por exemplo. A chave é a identidade do app: **trocar de chave obriga
todo mundo a desinstalar e instalar de novo**, porque o Android recusa
atualização assinada por outra chave. Perder a chave tem o mesmo efeito.

Nunca comite o `.keystore` nem o `.b64`.

#### A primeira instalação depois de assinar

Quem já tem o APK antigo (assinado com a chave de depuração) precisa
**desinstalar antes** de instalar o novo — as assinaturas são diferentes, e o
Android bloqueia a atualização. Depois disso, as próximas atualizações entram
normalmente.

### Sem aviso nenhum: Play Store

Publicar em teste interno na Play Store acaba com o aviso e dá atualização
automática. Custa US$ 25 uma vez pela conta de desenvolvedor, exige política de
privacidade publicada (o app guarda dados de menores, então isso é necessário
de qualquer forma) e passa por revisão.

## Gerar APK

Duas formas, dependendo do que você precisa:

**PWABuilder (mais simples, sem recursos nativos)** — depois de publicado, use
https://www.pwabuilder.com/ com a URL do site publicado pra gerar o APK.

**App nativo Android via Capacitor (recursos nativos: vibração, câmera, barra
de status)** — o mesmo HTML/CSS/JS é empacotado num app Android de verdade,
usando [Capacitor](https://capacitorjs.com). O site publicado no Cloudflare
não muda em nada — isso só gera o APK.

Pré-requisitos: Node.js, [Android Studio](https://developer.android.com/studio)
(ou Android SDK + Gradle) instalados.

```bash
npm install          # instala o Capacitor e os plugins (uma vez só)
npm run android:open # gera www/, sincroniza o projeto android/ e abre no Android Studio
```

No Android Studio: **Build → Build Bundle(s) / APK(s) → Build APK(s)**.

Sempre que mudar `index.html`/`login.html`/etc., rode `npm run cap:sync`
antes de gerar um novo APK (ou simplesmente `npm run android:open` de novo).

O app nativo já vem com:
- Vibração leve (haptics) ao tocar em botões e na navegação inferior
- Barra de status com a cor do tema do app
- Câmera/galeria nos uploads de foto (já funcionam via `<input type="file">`,
  sem precisar do plugin de câmera nativo)

O projeto Android fica em `android/` (versionado no repositório — só os
diretórios de build/cache são ignorados, ver `.gitignore`). `package.json`,
`android/`, `scripts/` e `capacitor.config.json` ficam de fora do site
publicado (ver `.assetsignore`).

Toda vez que algo em `index.html`/`android/**` muda, o workflow
`.github/workflows/android-build.yml` compila o APK automaticamente e
disponibiliza como artifact na aba **Actions** do repositório — dá pra
baixar e instalar sem precisar rodar nada localmente.

## iOS

**Sem conta Apple Developer (grátis, funciona hoje):** no Safari do iPhone,
abra o site publicado → **Compartilhar → Adicionar à Tela de Início**. Vira
um app instalado de verdade (ícone próprio, tela cheia, funciona offline) —
as meta tags necessárias (`apple-mobile-web-app-capable`, `apple-touch-icon`
etc.) já estão no `index.html`.

**App nativo via Capacitor (recursos nativos, como o Android):** a estrutura
já está pronta em `ios/` — mesmos plugins (haptics, câmera, barra de status).
Mas compilar/assinar um app iOS **só é possível num Mac com Xcode**, e pra
instalar em qualquer iPhone que não seja o seu (ex.: TestFlight) é preciso
uma conta **Apple Developer paga (US$ 99/ano)** — isso eu não posso criar
por você. Com a conta em mãos:

```bash
npm install
npm run ios:open   # gera www/, sincroniza o projeto ios/ e abre no Xcode
```

No Xcode: configure o **Team** (sua conta Apple Developer) em Signing &
Capabilities, e use **Product → Archive** pra gerar o build.

Sem conta paga, ainda dá pra rodar no **seu próprio** iPhone via Xcode
(assinatura pessoal gratuita, válida por 7 dias, só nesse aparelho). O
workflow `.github/workflows/ios-build.yml` compila o projeto pro Simulador
a cada mudança (sem precisar de assinatura), só pra confirmar que nada
quebrou — não gera um `.ipa` instalável num iPhone real.
