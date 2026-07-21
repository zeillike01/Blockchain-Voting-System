import React from 'react';
import { Link, useLocation } from 'wouter';
import { useWallet } from '@/context/WalletContext';
import { WrongNetworkBanner } from '@/components/wrong-network-banner';
import { Button } from '@/components/ui/button';
import { Sidebar, SidebarContent, SidebarFooter, SidebarHeader, SidebarMenu, SidebarMenuItem, SidebarMenuButton, SidebarProvider } from '@/components/ui/sidebar';
import { Landmark, Vote, BarChart3, Settings, ShieldCheck, Droplet } from 'lucide-react';

export function AppLayout({ children }: { children: React.ReactNode }) {
  const [location] = useLocation();
  const { isConnected, address, connect, disconnect, copyAddressAndOpenFaucet } = useWallet();

  const truncateAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

  return (
    <SidebarProvider>
      <div className="min-h-[100dvh] flex w-full bg-background">
        <Sidebar className="border-r-sidebar-border text-sidebar-foreground bg-sidebar">
          <SidebarHeader className="p-4 border-b border-sidebar-border">
            <Link href="/" className="flex items-center gap-3 hover:opacity-90 transition-opacity">
              <div className="bg-primary rounded p-1.5 flex items-center justify-center">
                <Landmark className="h-6 w-6 text-white" />
              </div>
              <div className="flex flex-col">
                
                <span className="text-xs text-sidebar-foreground/70">Soulbound Voting System</span>
              </div>
            </Link>
          </SidebarHeader>

          <SidebarContent className="p-2">
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton asChild isActive={location === '/'} tooltip="Home">
                  <Link href="/">
                    <ShieldCheck />
                    <span>Home</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
              
              <SidebarMenuItem>
                <SidebarMenuButton asChild isActive={location.startsWith('/vote')} tooltip="Voter Hub">
                  <Link href="/vote">
                    <Vote />
                    <span>Voter Hub</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>

              <SidebarMenuItem>
                <SidebarMenuButton asChild isActive={location.startsWith('/results')} tooltip="Results">
                  <Link href="/results">
                    <BarChart3 />
                    <span>Public Results</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>

              <SidebarMenuItem>
                <SidebarMenuButton asChild isActive={location.startsWith('/admin')} tooltip="Admin">
                  <Link href="/admin">
                    <Settings />
                    <span>Admin Panel</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarContent>

          <SidebarFooter className="p-4 border-t border-sidebar-border space-y-4">
            {isConnected ? (
              <div className="space-y-3">
                <div className="flex flex-col gap-1">
                  <span className="text-xs text-sidebar-foreground/60 uppercase tracking-wider font-semibold">Connected Wallet</span>
                  <div className="flex items-center justify-between bg-sidebar-accent/50 rounded-md px-3 py-2 border border-sidebar-border">
                    <span className="text-sm font-medium text-white font-mono" data-testid="text-wallet-address">{truncateAddress(address!)}</span>
                    <div className="h-2 w-2 rounded-full bg-green-500" title="Connected"></div>
                  </div>
                </div>
                
                <Button 
                  variant="outline" 
                  size="sm" 
                  className="w-full justify-start text-xs bg-sidebar-accent hover:bg-sidebar-accent/80 hover:text-white border-sidebar-border text-sidebar-foreground" 
                  onClick={copyAddressAndOpenFaucet}
                  data-testid="button-faucet"
                >
                  <Droplet className="mr-2 h-4 w-4 text-accent" />
                  Get CREDIT (Faucet)
                </Button>

                <Button 
                  variant="ghost" 
                  size="sm" 
                  className="w-full justify-start text-xs text-sidebar-foreground/70 hover:text-white hover:bg-sidebar-accent"
                  onClick={disconnect}
                  data-testid="button-disconnect"
                >
                  Disconnect
                </Button>
              </div>
            ) : (
              <div className="space-y-2 text-center">
                <span className="text-xs text-sidebar-foreground/60">Not connected</span>
                <Button 
                  onClick={connect} 
                  className="w-full bg-primary hover:bg-primary/90 text-primary-foreground font-semibold"
                  data-testid="button-connect-sidebar"
                >
                  Connect Wallet
                </Button>
              </div>
            )}
          </SidebarFooter>
        </Sidebar>

        <main className="flex-1 flex flex-col relative overflow-y-auto">
          <WrongNetworkBanner />
          <div className="flex-1 p-6 md:p-10 max-w-7xl mx-auto w-full">
            {children}
          </div>
        </main>
      </div>
    </SidebarProvider>
  );
}
