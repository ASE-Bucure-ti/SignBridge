# =============================================================================
# SignBridge Test App — Multi-stage Docker build
# Stage 1: Build Vite frontend
# Stage 2: Slim runtime (Express serves API + static files)
# =============================================================================

# ── Build stage ───────────────────────────────────────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

# Install dependencies first (cache layer)
COPY package.json package-lock.json* ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM node:20-alpine AS runtime

WORKDIR /app

# Only production deps + tsx for running TypeScript server
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm install tsx

# Copy server source (TypeScript, runs via tsx)
COPY server/ ./server/
COPY shared/ ./shared/
COPY tsconfig.json tsconfig.node.json ./

# Copy built frontend from build stage
COPY --from=build /app/dist ./dist

ENV NODE_ENV=production
ENV PORT=3001

EXPOSE 3001

CMD ["node", "--import", "tsx", "server/index.ts"]
