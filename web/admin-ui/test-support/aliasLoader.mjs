import { existsSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const srcDir = path.resolve(import.meta.dirname, '..', 'src');
const extensions = ['.js', '.mjs', '.jsx', '.ts', '.tsx'];

function resolveLocalFile(basePath) {
  if (existsSync(basePath) && !existsSync(path.join(basePath, 'index.js'))) {
    return basePath;
  }

  for (const extension of extensions) {
    if (existsSync(`${basePath}${extension}`)) {
      return `${basePath}${extension}`;
    }
  }

  for (const extension of extensions) {
    const indexPath = path.join(basePath, `index${extension}`);
    if (existsSync(indexPath)) {
      return indexPath;
    }
  }

  return basePath;
}

const isRelative = (specifier) => specifier.startsWith('./') || specifier.startsWith('../');
const hasExtension = (specifier) => path.extname(specifier) !== '';

// The `next` package ships no exports map, so plain Node cannot resolve the
// extensionless `next/server` specifier that Next's bundler understands.
const nextServerPath = path.resolve(import.meta.dirname, '..', 'node_modules', 'next', 'server.js');

export async function resolve(specifier, context, nextResolve) {
  if (specifier === 'next/server' && existsSync(nextServerPath)) {
    return nextResolve(pathToFileURL(nextServerPath).href, context);
  }

  if (specifier.startsWith('@/')) {
    const target = resolveLocalFile(path.join(srcDir, specifier.slice(2)));
    return nextResolve(pathToFileURL(target).href, context);
  }

  if (isRelative(specifier) && !hasExtension(specifier) && context.parentURL) {
    const basePath = path.resolve(path.dirname(new URL(context.parentURL).pathname), specifier);
    const target = resolveLocalFile(basePath);
    if (target !== basePath) {
      return nextResolve(pathToFileURL(target).href, context);
    }
  }

  return nextResolve(specifier, context);
}
