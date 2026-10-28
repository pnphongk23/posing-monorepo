import { NextResponse } from 'next/server';

import { checkAdminBasicAuth } from './lib/adminBasicAuth.js';

/**
 * Next.js 16 renamed the `middleware` file convention to `proxy`
 * (Node.js runtime only), so this file is `src/proxy.js` rather than
 * `src/middleware.js`. Every request that reaches this app - pages, server
 * actions, route handlers, all HTTP methods - passes through here before the
 * filesystem/app routes run.
 */
export function proxy(request) {
  const denied = checkAdminBasicAuth(request.headers.get('authorization'), process.env);

  if (denied) {
    return new NextResponse(denied.body, {
      status: denied.status,
      headers: denied.headers,
    });
  }

  return NextResponse.next();
}

export const config = {
  // Gate every path except Next.js' own immutable build output.
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
