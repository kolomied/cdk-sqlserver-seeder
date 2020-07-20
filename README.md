# cdk-sqlserver-seeder [![Mentioned in Awesome CDK](https://awesome.re/mentioned-badge.svg)](https://github.com/eladb/awesome-cdk)
![build](https://github.com/kolomied/cdk-sqlserver-seeder/workflows/build/badge.svg)
![jsii-publish](https://github.com/kolomied/cdk-sqlserver-seeder/workflows/jsii-publish/badge.svg)
![downloads](https://img.shields.io/npm/dt/cdk-sqlserver-seeder)

[![npm version](https://badge.fury.io/js/cdk-sqlserver-seeder.svg)](https://badge.fury.io/js/cdk-sqlserver-seeder)
[![PyPI version](https://badge.fury.io/py/cdk-sqlserver-seeder.svg)](https://badge.fury.io/py/cdk-sqlserver-seeder)
[![NuGet version](https://badge.fury.io/nu/Talnakh.SqlServerSeeder.svg)](https://badge.fury.io/nu/Talnakh.SqlServerSeeder)
[![Maven Central](https://img.shields.io/maven-central/v/xyz.talnakh/SqlServerSeeder?color=brightgreen)](https://repo1.maven.org/maven2/xyz/talnakh/SqlServerSeeder/)

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

        const seeder = new SqlServerSeeder(this, "SqlSeeder", { 
            database: sqlServer,
            port: 1433,
            vpc: vpc,
            createScriptPath: "./SQL/v1.0.0.sql", // script to be executed on resource creation
            deleteScriptPath: "./SQL/cleanup.sql" // script to be executed on resource deletion
        });
    }
}
```

## Configuration properties
SqlServerSeeder construct accepts the following configuration properties:

| Parameter  | Required  | Default | Description |
|---|---|---|---|
| `vpc`              | yes |       | VPC for Lambda function deployment      | 
| `database`         | yes |       | RDS SQL Server database instance        |
| `createScriptPath` | yes |       | SQL scripts to run on resource creation |
| `deleteScriptPath` | no  |       | SQL script to run on resource deletion  |
| `port`             | no  | 1433  | RSD SQL Server database port            |
| `memorySize`       | no  | 512   | Lambda function memory size             |
| `ignoreSqlErrors`  | no  | false | Whether to ignore SQL error or not      |

## Architecture

![Architecture](/doc/architecture.png)

`cdk-sqlserver-seeder` deploys a custom resource backed by PowerShell lambda to connect to SQL Server instance. Lambda function is deployed in private subnets of your VPC where RDS instance resides.

Lambda function retrieves database credentials from [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) and uses them to construct connection string to the database.

SQL scripts are uploaded into S3 bucket during CDK application deployment.
Lambda function downloads these scripts during execution.

## Security considerations
Lambda function has the following permissions:

- Managed policies
   - `AWSLambdaBasicExecutionRole` for CloudWatch logs
   - `AWSLambdaVPCAccessExecutionRole` for VPC access
- Inline policy
  - `secretsmanager:GetSecretValue` for RDS credentials secret
  - `s3:GetObject*`, `s3:GetBucket*`, `s3:List*` for S3 bucket with SQL scripts

## Acknowledgements
The whole project inspired by [aws-cdk-dynamodb-seeder](https://github.com/elegantdevelopment/aws-cdk-dynamodb-seeder). 
I though it would be very helpful to have a similar way to seed initial schema to more traditional SQL Server databases.
