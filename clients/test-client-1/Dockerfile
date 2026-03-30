FROM node:22-alpine

WORKDIR /app

RUN apk add --no-cache bash git curl

RUN git clone https://github.com/openclaw/openclaw.git /app/openclaw

WORKDIR /app/openclaw

RUN npm install --omit=dev

RUN adduser -D -u 1001 client

USER 1001

# Pre-build TypeScript
RUN node scripts/tsdown-build.mjs

CMD ["node", "dist/index.mjs"]
