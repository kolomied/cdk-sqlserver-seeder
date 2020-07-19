# aws-cdk-sqlserver-seeder
![build](https://github.com/kolomied/cdk-sqlserver-seeder/workflows/build/badge.svg)
[![dependencies](https://david-dm.org/kolomied/cdk-sqlserver-seeder.svg)](https://david-dm.org//kolomied/cdk-sqlserver-seeder)

A simple CDK seeder for SQL Server RDS databases.

## Usage

```typescript
import * as cdk from '@aws-cdk/core';
import * as ec2 from '@aws-cdk/aws-ec2';
import * as rds from '@aws-cdk/aws-rds';
import { SqlServerSeeder } from 'cdk-sqlserver-seeder';

export class DatabaseStack extends cdk.Stack {
    constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
        super(scope, id, props);

        const sqlServer = new rds.DatabaseInstance(this, 'Instance', {
            engine: rds.DatabaseInstanceEngine.SQL_SERVER_WEB,
            // all other properties removed for clarity
        });

        const seeder = new SqlSeederSecret(this, "SqlSeederSecret", { 
            database: sqlServer,
            port: 1433,
            vpc: vpc,
            createScriptPath: "./SQL/v1.0.0.sql", // script to be executed on resource creation
            deleteScriptPath: "./SQL/cleanup.sql" // script to be executed on resource deletion
        });
    }
}
```

## Acknowledgements
The whole project inspired by [aws-cdk-dynamodb-seeder](https://github.com/elegantdevelopment/aws-cdk-dynamodb-seeder). 
I though it would be very helpful to have a similar way to seed initial schema to more traditional SQL Server databases.
