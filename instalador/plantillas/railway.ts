// Infraestructura de Railway como código (SDK railway/iac, paquete railway@3.11.0, Node 22 o más).
// Lo generó instalador/instalar.sh. En cada ambiente (production y staging): railway environment
// link con el ambiente, railway config plan para revisar el cambio y railway config apply.
import { defineRailway, project, service } from 'railway/iac'

// IaC parcial: este repo administra solo los recursos que declara aquí.
export const partial = '{{repo}}'

export default defineRailway(() => {
  const app = service('{{servicio}}', {
    healthcheck: '/health',
    healthcheckTimeout: 120,
    deploy: { restartPolicyType: 'ON_FAILURE', restartPolicyMaxRetries: 3 },
  })
  return project('{{repo}}', {
    resources: [app],
  })
})
