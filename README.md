# cdk-sqlserver-seeder
![build](https://github.com/kolomied/cdk-sqlserver-seeder/workflows/build/badge.svg)
[![dependencies](https://david-dm.org/kolomied/cdk-sqlserver-seeder.svg)](https://david-dm.org//kolomied/cdk-sqlserver-seeder)

[![npm version](https://badge.fury.io/js/cdk-sqlserver-seeder.svg)](https://badge.fury.io/js/cdk-sqlserver-seeder)
[![PyPI version](https://badge.fury.io/py/cdk-sqlserver-seeder.svg)](https://badge.fury.io/py/cdk-sqlserver-seeder)
[![NuGet version](https://badge.fury.io/nu/Talnakh.SqlServerSeeder.svg)](https://badge.fury.io/nu/Talnakh.SqlServerSeeder)

A simple CDK seeder for SQL Server RDS databases.

*cdk-sqlserver-seeder* library is a [AWS CDK](https://aws.amazon.com/cdk/) construct that provides a way 
to execute custom SQL scripts on RDS SQL Server resource creation/deletion.

The construct relies on [Invoke-SqlCmd](https://docs.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd) cmdlet 
to run the scripts and handle possible errors. Provides a way to handle transient errors during stack provisioning.

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
