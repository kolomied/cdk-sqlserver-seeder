import * as cdk from '@aws-cdk/core';
import * as ec2 from '@aws-cdk/aws-ec2';
import * as lambda from '@aws-cdk/aws-lambda';
import * as rds from '@aws-cdk/aws-rds';
import * as cr from '@aws-cdk/custom-resources';
import * as s3 from '@aws-cdk/aws-s3';
import { BucketDeployment, Source } from '@aws-cdk/aws-s3-deployment';
import * as tmp from 'tmp';
import * as fs from 'fs';
import * as path from 'path';

export interface SqlServerSeederProps {
  readonly vpc: ec2.IVpc;
  readonly database: rds.DatabaseInstance,
  readonly port: number,

  readonly createScriptPath: string,
  readonly deleteScriptPath?: string,

  /**
   * The amount of memory, in MB, that is allocated to custom resource's Lambda function.
   * May require some tweaking for "hunger" SQL scripts.
   * @default 512
   */
  readonly memorySize?: number,

  /**
   * Flag that allows to ignore SQL errors.
   * May be helpful during troubleshooting.
   * @default false
   */
  readonly ignoreSqlErrors?: boolean
}

export class SqlServerSeeder extends cdk.Construct {

  constructor(scope: cdk.Construct, id: string, props: SqlServerSeederProps) {
    super(scope, id);

    if (!props.database.secret) {
      throw new Error("Database does not have secret value assigned");
    }
    if (!fs.existsSync(props.createScriptPath)) {
      throw new Error("Create script does not exist: " + props.createScriptPath);
    }
    if (props.deleteScriptPath && !fs.existsSync(props.deleteScriptPath)) {
      throw new Error("Create script does not exist: " + props.deleteScriptPath);
    }

    const destinationBucket = new s3.Bucket(this, 'bucket', { removalPolicy: cdk.RemovalPolicy.DESTROY });
    this.prepareSqlScripts(id, props, destinationBucket);

    const sqlSeederLambda = new lambda.Function(this, 'lambda', {
      code: new lambda.AssetCode('./lambda/sqlserver-seeder.zip'),
      handler: 'seed::seed.Bootstrap::ExecuteFunction',
      timeout: cdk.Duration.seconds(300),
      runtime: lambda.Runtime.DOTNET_CORE_3_1,
      memorySize: props.memorySize,
      vpc: props.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE
      },
      environment: {
        "DbEndpoint": props.database.dbInstanceEndpointAddress,
        "SecretArn": props.database.secret?.secretArn,
        "ScriptsBucket": destinationBucket.bucketName,
        "RunOnDelete": `${!!props.deleteScriptPath}`
      }
    });

    const sqlSeederProvider = new cr.Provider(this, 'provider', {
      onEventHandler: sqlSeederLambda
    });
    const sqlSeederResource = new cdk.CustomResource(this, 'resource', {
      serviceToken: sqlSeederProvider.serviceToken,
      properties: {
        "IgnoreSqlErrors": !!props.ignoreSqlErrors
      }
    });
    sqlSeederResource.node.addDependency(props.database);

    // allow access
    destinationBucket.grantRead(sqlSeederLambda);
    props.database.secret?.grantRead(sqlSeederLambda);

    // enable connection to RDS instance
    sqlSeederLambda.connections.allowTo(props.database, ec2.Port.tcp(props.port));
  }

  private prepareSqlScripts(id: string, props: SqlServerSeederProps, destinationBucket: s3.Bucket) {
    tmp.setGracefulCleanup();
    tmp.dir((err, dir) => {
      if (err)
        throw err;

      fs.copyFileSync(props.createScriptPath, path.join(dir, 'create.sql'));

      if (props.deleteScriptPath) {
        fs.copyFileSync(props.deleteScriptPath, path.join(dir, 'delete.sql'));
      }

      new BucketDeployment(this, id, {
        sources: [Source.asset(dir)],
        destinationBucket,
        retainOnDelete: false
      });
    });
  }
}
