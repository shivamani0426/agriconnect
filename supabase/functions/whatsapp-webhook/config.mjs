// Existing test number is the backward-compatible default. Override both IDs together.
// These IDs are not credentials. Never accept URL/path fragments or partial overrides.
export const PHONE_ID='1456298224232496';
export const WABA_ID='2111995459517329';
export const validMetaId=id=>typeof id==='string'&&/^[1-9][0-9]{5,31}$/.test(id);
export function resolveSender(env){
 const phone=env('WA_PHONE_NUMBER_ID'),waba=env('WA_BUSINESS_ACCOUNT_ID');
 if(phone===undefined&&waba===undefined)return {phoneId:PHONE_ID,wabaId:WABA_ID,source:'legacy_default'};
 if(!validMetaId(phone)||!validMetaId(waba))return null;
 return {phoneId:phone,wabaId:waba,source:'configured'};
}
export const graphBase='https://graph.facebook.com/v25.0/';
