import React from 'react';
import { ExternalLink, FileWarning } from 'lucide-react';
import { SKALE_BASE_SEPOLIA } from '@/config/chain';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';

export function ContractNotDeployed() {
  return (
    <Card className="max-w-md mx-auto mt-12 text-center" data-testid="card-contract-not-deployed">
      <CardHeader>
        <div className="mx-auto bg-muted w-16 h-16 rounded-full flex items-center justify-center mb-4">
          <FileWarning className="h-8 w-8 text-muted-foreground" />
        </div>
        <CardTitle className="text-xl">Contract Not Deployed</CardTitle>
        <CardDescription>
          The smart contract for this feature has not been deployed yet. Please check back later.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Button variant="outline" className="w-full" asChild data-testid="link-skale-explorer">
          <a href={SKALE_BASE_SEPOLIA.blockExplorerUrls[0]} target="_blank" rel="noopener noreferrer">
            <ExternalLink className="mr-2 h-4 w-4" />
            View SKALE Explorer
          </a>
        </Button>
      </CardContent>
    </Card>
  );
}
