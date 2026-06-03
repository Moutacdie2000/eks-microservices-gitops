# syntax=docker/dockerfile:1

############################
# Étape 1, dépendances
############################
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

############################
# Étape 2, runtime
############################
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

RUN addgroup -S nodegrp && adduser -S nodeusr -G nodegrp

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER nodeusr
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
