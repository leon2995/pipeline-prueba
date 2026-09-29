# Criterios: vencimiento-token (PR sin rutas de gobierno de la verificación del paso f)

Riesgo: **bajo**. Solo documentación: `README.md` y `SETUP.md`, que no son rutas de gobierno. Es el primer PR que abre `talos-bot-leon` y el primero que el CTO mergea a `staging` con 0 aprobaciones (punto 1 del paso g). Sirve para verificar que el push, el commit y el PR salen como `talos-bot-leon`.

- **C1.** `README.md` describe el repositorio en una línea, remite a `CLAUDE.md` y `SETUP.md` y nombra la cuenta del agente.
- **C2.** `SETUP.md`, paso c:
  - el campo de vencimiento dice `2026-10-29`, que es el vencimiento real que responde GitHub en la cabecera `GitHub-Authentication-Token-Expiration`;
  - la fecha límite para rotarlo es `2026-10-15`, con la indicación de responder No a la pregunta de Git al repetir el login;
  - la decisión de Leonardo de dejar el token con más scopes que el mínimo queda documentada, con su razón y la condición de revisarla si `talos-bot-leon` se agrega a otros repos u organizaciones.
- **C3.** `SETUP.md`, paso c, verifica con `gh auth status` que el token sea classic (`ghp_`, con al menos `repo`, `workflow` y `read:org` o `admin:org`) y dice cómo ver el vencimiento real. Un `github_pat_` (fine-grained) lee el repo público pero da 403 al empujar, como pasó en la primera verificación del paso f. Además trae el remedio para quien respondió Sí a "Authenticate Git with your GitHub credentials?", en tres pasos:
  1. `git credential-manager github logout talos-bot-leon`;
  2. `git credential-manager github login --username leon2995 --device`, confirmando en el navegador que la sesión sea `leon2995` y no el bot;
  3. la verificación: `github list`, la configuración global de credenciales y el comando que consulta a GitHub con el token guardado sin imprimirlo (`git credential fill | sed -n 's/^password=//p' | { read -r t && [ -n "$t" ] && GH_TOKEN="$t" gh api user --jq .login || echo 'sin credencial guardada'; }`), que debe responder `leon2995` y no cae a la cuenta propia de gh si no hay credencial guardada. *Forma corregida en el reintento 1.*

  Aclara que lo corre Leonardo en su terminal y no el agente, y por qué la etiqueta `username=` no alcanza. El texto lo pidió Leonardo después de aplicar ese remedio en el paso c.
- **C4.** Ningún comando documentado imprime un token.
- **C5.** Los commits de la rama tienen autor y committer `talos-bot-leon <335185800+talos-bot-leon@users.noreply.github.com>`.

Verificación posterior al PASS (fuera de los criterios del auditor, según LESSONS.md): CI del PR en verde; el push y el PR salen como `talos-bot-leon` (`gh pr view --json author,commits` y actividad de la rama); el mensaje del squash corrige la fecha vieja (2026-12-27) del primer commit.
