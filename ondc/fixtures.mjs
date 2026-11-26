export const FPO_A='a0000000-0000-4000-8000-000000000001',FPO_B='a0000000-0000-4000-8000-000000000002',FPO_C='a0000000-0000-4000-8000-000000000003';
export const rows=[
 {fpo_id:FPO_A,fpo_name:'Demo Green FPO',crop:'Tomatoes',grade:'A',price_paise_per_kg:3000,available_kg:'25.500'},
 {fpo_id:FPO_A,fpo_name:'Demo Green FPO',crop:'Onions',grade:'B',price_paise_per_kg:2250,available_kg:'6.000'},
 {fpo_id:FPO_B,fpo_name:'Demo Valley FPO',crop:'Tomatoes',grade:'B',price_paise_per_kg:1800,available_kg:'4.000'},
 {fpo_id:FPO_B,fpo_name:'Demo Valley FPO',crop:'Beans',grade:'A',price_paise_per_kg:4000,available_kg:'0.000'},
 {fpo_id:FPO_A,fpo_name:'Demo Green FPO',crop:'Seeds',grade:'A',price_paise_per_kg:8000,available_kg:'8.000'},
 {fpo_id:FPO_C,fpo_name:'Unlisted demo FPO',crop:'Tomatoes',grade:'A',price_paise_per_kg:2000,available_kg:'10.000'}
];
export const eligibility=new Map([[FPO_A,{city:'std:080',crops:['Tomatoes','Onions']}],[FPO_B,{city:'std:080',crops:['Tomatoes','Beans']}]]);
