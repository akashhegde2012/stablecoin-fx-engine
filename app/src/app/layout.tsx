import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { AppProviders } from "@/components/providers/AppProviders";
import { Header }       from "@/components/Header";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title:       "KAIA FX — Multi-currency DEX",
  description: "Swap Southeast Asian stablecoins on the KAIA blockchain",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={inter.className}>
        <AppProviders>
          <div className="min-h-screen bg-kaia-bg">
            <Header />
            <main>{children}</main>
          </div>
        </AppProviders>
      </body>
    </html>
  );
}
