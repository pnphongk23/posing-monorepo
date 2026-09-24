import "./globals.css";

export const viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: "cover",
  themeColor: "#f6f1e8",
};

export const metadata = {
  title: "posing admin",
  description: "Upload a photo, extract the pose as line art, and use it as a camera overlay guide to recreate perfect poses.",
  keywords: ["pose", "camera", "AI", "line art", "photography", "pose guide"],
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "posing",
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" className="h-full">
      <body className="h-full font-sans antialiased bg-bg-primary text-text-primary">
        {children}
      </body>
    </html>
  );
}
