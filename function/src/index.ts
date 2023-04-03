import { APIGatewayProxyHandler } from 'aws-lambda';
import axios from 'axios';
import crypto from 'crypto';
import * as queryString from 'querystring';
import { SecretsManager } from 'aws-sdk';

const secretsManager = new SecretsManager();
const baseUrl = 'https://api.binance.com';

const getBinanceApiKeys = async (): Promise<{ apiKey: string; secretKey: string }> => {
  const secret = await secretsManager
    .getSecretValue({ SecretId: 'binance-api-keys' })
    .promise();

  if (!secret.SecretString) {
    throw new Error('Unable to retrieve Binance API keys');
  }

  const parsedSecret = JSON.parse(secret.SecretString);
  return {
    apiKey: parsedSecret.BINANCE_API_KEY,
    secretKey: parsedSecret.BINANCE_SECRET_KEY,
  };
};

const createSignature = async(data: string) => {
    const { secretKey } = await getBinanceApiKeys();
    return crypto
        .createHmac('sha256', secretKey)
        .update(data)
        .digest('hex');
};

export const handler: APIGatewayProxyHandler = async (event, _context) => {
    const timestamp = Date.now();
    const queryParams = {
        timestamp,
        recvWindow: 5000,
    };

    const { apiKey } = await getBinanceApiKeys();

    const queryStringParams = queryString.stringify(queryParams);
    const signature = createSignature(queryStringParams);
    const url = `${baseUrl}/api/v3/account?${queryStringParams}&signature=${signature}`;

    try {
        const response = await axios.get(url, {
            headers: { 'X-MBX-APIKEY': apiKey },
        });

        return {
            statusCode: 200,
            body: JSON.stringify(response.data),
        };
    } catch (error) {
        console.error('Error fetching Binance account trade list user data:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: 'Error fetching Binance account trade list user data' }),
        };
    }
};
