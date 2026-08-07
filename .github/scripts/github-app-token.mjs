#!/usr/bin/env node
import { createSign } from "node:crypto";

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function normalizePrivateKey(value) {
  return value.replace(/\\n/g, "\n");
}

function parseRepositories(value) {
  return value
    .split(/[\n,]/g)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

async function githubFetch(url, options) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(options.headers ?? {}),
    },
  });
  const bodyText = await response.text();
  const body = bodyText ? JSON.parse(bodyText) : {};
  if (!response.ok) {
    throw new Error(
      `GitHub API ${response.status} ${response.statusText}: ${JSON.stringify(body)}`,
    );
  }
  return body;
}

function createJwt(clientId, privateKey) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
  const payload = base64UrlJson({
    iat: now - 60,
    exp: now + 9 * 60,
    iss: clientId,
  });
  const unsigned = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");
  signer.update(unsigned);
  signer.end();
  return `${unsigned}.${signer.sign(privateKey).toString("base64url")}`;
}

const owner = requiredEnv("GITHUB_APP_OWNER");
const repositories = parseRepositories(requiredEnv("GITHUB_APP_REPOSITORIES"));
const clientId = requiredEnv("GITHUB_APP_CLIENT_ID");
const privateKey = normalizePrivateKey(requiredEnv("GITHUB_APP_PRIVATE_KEY"));
const permissions = process.env.GITHUB_APP_PERMISSIONS_JSON
  ? JSON.parse(process.env.GITHUB_APP_PERMISSIONS_JSON)
  : {};

const jwt = createJwt(clientId, privateKey);
const firstRepository = repositories[0];
const installation = await githubFetch(
  `https://api.github.com/repos/${owner}/${firstRepository}/installation`,
  {
    headers: {
      Authorization: `Bearer ${jwt}`,
    },
  },
);

const tokenResponse = await githubFetch(
  `https://api.github.com/app/installations/${installation.id}/access_tokens`,
  {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      repositories,
      permissions,
    }),
  },
);

process.stdout.write(
  JSON.stringify({
    token: tokenResponse.token,
    expires_at: tokenResponse.expires_at,
  }),
);
