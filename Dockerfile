# Aktuelles LTS-Basis-Image (Node 24, Debian slim) statt node:18 (End-of-Life).
# Mit Digest gepinnt, Dependabot hält es aktuell (.github/dependabot.yml).
FROM node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54

ENV NEXT_TELEMETRY_DISABLED=1
WORKDIR /app
RUN chown node:node /app

# Nicht als root laufen
USER node

COPY --chown=node:node package*.json ./
RUN npm ci

COPY --chown=node:node . .
# Nach dem Build die Entwicklungswerkzeuge (z.B. ESLint) wieder entfernen
RUN npm run build && npm prune --omit=dev && npm cache clean --force

ENV NODE_ENV=production
EXPOSE 3000
CMD ["npm", "start"]
