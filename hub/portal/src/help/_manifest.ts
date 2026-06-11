import type { FormHelp, WorkflowHelp, RoleHelp } from './types'
import type { HowToEntry } from './how-to/_index'

import assessmentFields from './forms/assessment/fields'
import intakeCreateFields from './forms/intake-create/fields'
import applicationOnboardFields from './forms/application-onboard/fields'
import evidenceRecordFields from './forms/evidence-record/fields'
import exceptionRaiseFields from './forms/exception-raise/fields'
import changeProposalFields from './forms/change-proposal/fields'
import registryAssetFields from './forms/registry-asset/fields'

import intakeApprovalSteps from './workflows/intake-approval/steps'
import registryPromotionSteps from './workflows/registry-promotion/steps'
import obligationResolutionSteps from './workflows/obligation-resolution/steps'

import howToIndex from './how-to/_index'

export const helpManifest = {
  forms: {
    assessment:             { fields: assessmentFields,           page: () => import('./forms/assessment/_page.html?raw') } as FormHelp,
    'intake-create':        { fields: intakeCreateFields,         page: () => import('./forms/intake-create/_page.html?raw') } as FormHelp,
    'application-onboard':  { fields: applicationOnboardFields,   page: () => import('./forms/application-onboard/_page.html?raw') } as FormHelp,
    'evidence-record':      { fields: evidenceRecordFields,       page: () => import('./forms/evidence-record/_page.html?raw') } as FormHelp,
    'exception-raise':      { fields: exceptionRaiseFields,       page: () => import('./forms/exception-raise/_page.html?raw') } as FormHelp,
    'change-proposal':      { fields: changeProposalFields,       page: () => import('./forms/change-proposal/_page.html?raw') } as FormHelp,
    'registry-asset':       { fields: registryAssetFields,        page: () => import('./forms/registry-asset/_page.html?raw') } as FormHelp,
  },
  workflows: {
    'intake-approval':        { steps: intakeApprovalSteps,         page: () => import('./workflows/intake-approval/_page.html?raw') } as WorkflowHelp,
    'registry-promotion':     { steps: registryPromotionSteps,      page: () => import('./workflows/registry-promotion/_page.html?raw') } as WorkflowHelp,
    'obligation-resolution':  { steps: obligationResolutionSteps,   page: () => import('./workflows/obligation-resolution/_page.html?raw') } as WorkflowHelp,
  },
  roles: {
    overview:    { page: () => import('./roles/_overview.html?raw') } as RoleHelp,
    underwriter: { page: () => import('./roles/underwriter.html?raw') } as RoleHelp,
    compliance:  { page: () => import('./roles/compliance-officer.html?raw') } as RoleHelp,
    risk:        { page: () => import('./roles/risk-manager.html?raw') } as RoleHelp,
  },
  'how-to': howToIndex as Record<string, HowToEntry>,
  overview: {
    product:  () => import('./overview/product.html?raw'),
    glossary: () => import('./overview/glossary.html?raw'),
  },
} as const
