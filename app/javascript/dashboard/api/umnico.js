/* global axios */
import ApiClient from './ApiClient';

class UmnicoAPI extends ApiClient {
  constructor() {
    super('umnico', { accountScoped: true });
  }

  getIntegrations(inboxId) {
    return axios.get(`${this.url}/integrations`, {
      params: { inbox_id: inboxId },
    });
  }

  sendOutbound({ inboxId, saId, destination, message }) {
    return axios.post(`${this.url}/send_outbound`, {
      inbox_id: inboxId,
      sa_id: saId,
      destination,
      message,
    });
  }
}

export default new UmnicoAPI();
