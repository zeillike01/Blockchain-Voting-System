import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from '@/components/ui/toaster';
import { TooltipProvider } from '@/components/ui/tooltip';
import NotFound from '@/pages/not-found';
import Home from '@/pages/home';
import VoterHub from '@/pages/voter-hub';
import VoteNational from '@/pages/vote-national';
import VoteBarangay from '@/pages/vote-barangay';
import AdminPanel from '@/pages/admin';
import Results from '@/pages/results';
import { Route, Switch, Router as WouterRouter } from 'wouter';
import { WalletProvider } from '@/context/WalletContext';
import { AppLayout } from '@/components/layout';

const queryClient = new QueryClient();

function Router() {
  return (
    <AppLayout>
      <Switch>
        <Route path="/" component={Home} />
        <Route path="/vote" component={VoterHub} />
        <Route path="/vote/national" component={VoteNational} />
        <Route path="/vote/barangay" component={VoteBarangay} />
        <Route path="/admin" component={AdminPanel} />
        <Route path="/results" component={Results} />
        <Route component={NotFound} />
      </Switch>
    </AppLayout>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <WalletProvider>
        <TooltipProvider>
          <WouterRouter base={import.meta.env.BASE_URL.replace(/\/$/, '')}>
            <Router />
          </WouterRouter>
          <Toaster />
        </TooltipProvider>
      </WalletProvider>
    </QueryClientProvider>
  );
}

export default App;
